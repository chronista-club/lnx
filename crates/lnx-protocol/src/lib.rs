//! どのアプリがどの Gear を使うか — 使用意思（assignment）と実行中 lease を分離する純粋な状態機械（I/O なし）。
//!
//! 接続方式や通信規格（MIDI / SysEx / USB Serial / QUIC）は Gear の裏に隠し、
//! アプリとユーザーからは「どのアプリがどの Gear を使うか」として一貫して扱う（`mem_1ChTKc23Veo6sEXMJ16mAf`）。
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

pub const PROTOCOL_VERSION: u32 = 1;
pub mod wire;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Assignment {
    pub client_id: Option<String>,
    pub revision: u64,
    pub expected: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Lease {
    pub session_id: String,
    pub token: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    Off,
    Waiting,
    Active,
    Releasing,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GearState {
    pub gear_id: String,
    pub profile_id: String,
    pub name: String,
    pub present: bool,
    pub assignment: Assignment,
    pub phase: Phase,
    pub lease: Option<Lease>,
    pub releasing_to: Option<String>,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum AccessError {
    #[error("unknown gear")]
    UnknownGear,
    #[error("unknown session")]
    UnknownSession,
    #[error("another application is assigned")]
    Conflict,
    #[error("state changed since confirmation")]
    StaleRevision,
    #[error("stale lease")]
    StaleLease,
    #[error("handoff is pending")]
    Pending,
    #[error("application already has a live session")]
    AlreadyConnected,
}

#[derive(Clone)]
pub struct Broker {
    pub gears: BTreeMap<String, GearState>,
    sessions: BTreeMap<String, String>,
    quiescent: BTreeSet<String>,
    boot_id: String,
    sequence: u64,
}

impl Broker {
    /// boot_id はサービス起動ごとの UUID。再起動前の token を再発行しない。
    pub fn new(boot_id: impl Into<String>) -> Self {
        Self {
            gears: BTreeMap::new(),
            sessions: BTreeMap::new(),
            quiescent: BTreeSet::new(),
            boot_id: boot_id.into(),
            sequence: 0,
        }
    }
    pub fn register_session(&mut self, session: &str, client: &str) -> Result<(), AccessError> {
        if self.sessions.contains_key(session) || self.sessions.values().any(|c| c == client) {
            return Err(AccessError::AlreadyConnected);
        }
        self.sessions.insert(session.into(), client.into());
        let waiting: Vec<_> = self
            .gears
            .iter()
            .filter(|(_, g)| {
                g.phase == Phase::Waiting && g.assignment.client_id.as_deref() == Some(client)
            })
            .map(|(id, _)| id.clone())
            .collect();
        for id in waiting {
            self.activate(&id);
        }
        Ok(())
    }
    pub fn add_gear(&mut self, id: &str, profile: &str, present: bool) {
        if self.gears.contains_key(id) {
            return;
        }
        self.gears.insert(
            id.into(),
            GearState {
                gear_id: id.into(),
                profile_id: profile.into(),
                name: id.into(),
                present,
                assignment: Assignment {
                    client_id: None,
                    revision: 0,
                    expected: matches!(profile, "roto" | "lpd8" | "nanokontrol" | "maru"),
                },
                phase: Phase::Off,
                lease: None,
                releasing_to: None,
            },
        );
    }
    pub fn enable(
        &mut self,
        id: &str,
        session: &str,
        revision: u64,
        takeover: bool,
    ) -> Result<(), AccessError> {
        let client = self
            .sessions
            .get(session)
            .ok_or(AccessError::UnknownSession)?
            .clone();
        let gear = self.gears.get_mut(id).ok_or(AccessError::UnknownGear)?;
        if gear.assignment.revision != revision {
            return Err(AccessError::StaleRevision);
        }
        if gear.phase == Phase::Releasing {
            return Err(AccessError::Pending);
        }
        if gear.assignment.client_id.as_deref() == Some(&client) {
            return Ok(());
        }
        if gear.assignment.client_id.is_some() && !takeover {
            return Err(AccessError::Conflict);
        }
        gear.assignment.client_id = Some(client.clone());
        gear.assignment.revision += 1;
        if gear.lease.is_some() {
            gear.phase = Phase::Releasing;
            gear.releasing_to = Some(client);
            self.quiescent.remove(id);
        } else {
            self.activate(id);
        }
        Ok(())
    }
    pub fn disable(&mut self, id: &str, session: &str, revision: u64) -> Result<(), AccessError> {
        let client = self
            .sessions
            .get(session)
            .ok_or(AccessError::UnknownSession)?;
        let gear = self.gears.get_mut(id).ok_or(AccessError::UnknownGear)?;
        if gear.assignment.revision != revision {
            return Err(AccessError::StaleRevision);
        }
        if gear
            .assignment
            .client_id
            .as_ref()
            .is_some_and(|c| c != client)
        {
            return Err(AccessError::Conflict);
        }
        if gear.assignment.client_id.is_none() {
            return Ok(());
        }
        gear.assignment.client_id = None;
        gear.assignment.revision += 1;
        gear.releasing_to = None;
        if gear.lease.is_some() {
            gear.phase = Phase::Releasing;
        } else {
            gear.phase = Phase::Off;
        }
        Ok(())
    }
    pub fn quiesced(&mut self, id: &str, session: &str, token: &str) -> Result<(), AccessError> {
        let gear = self.gears.get(id).ok_or(AccessError::UnknownGear)?;
        if gear.phase != Phase::Releasing
            || !gear
                .lease
                .as_ref()
                .is_some_and(|l| l.session_id == session && l.token == token)
        {
            return Err(AccessError::StaleLease);
        }
        self.quiescent.insert(id.into());
        Ok(())
    }
    /// adapter の送信キュー停止・in-flight 完了後に runtime が呼ぶ。
    pub fn drained(&mut self, id: &str) -> Result<(), AccessError> {
        let gear = self.gears.get_mut(id).ok_or(AccessError::UnknownGear)?;
        if gear.phase != Phase::Releasing || !self.quiescent.remove(id) {
            return Err(AccessError::Pending);
        }
        gear.lease = None;
        gear.releasing_to = None;
        self.activate(id);
        Ok(())
    }
    pub fn authorize_output(
        &self,
        id: &str,
        session: &str,
        token: &str,
    ) -> Result<(), AccessError> {
        let gear = self.gears.get(id).ok_or(AccessError::UnknownGear)?;
        if gear.phase == Phase::Active
            && gear
                .lease
                .as_ref()
                .is_some_and(|l| l.session_id == session && l.token == token)
        {
            Ok(())
        } else {
            Err(AccessError::StaleLease)
        }
    }
    pub fn disconnect_session(&mut self, session: &str) {
        self.sessions.remove(session);
        for (id, gear) in &mut self.gears {
            if gear.lease.as_ref().is_some_and(|l| l.session_id == session) {
                gear.phase = Phase::Releasing;
                self.quiescent.insert(id.clone());
            }
        }
    }
    pub fn set_present(&mut self, id: &str, present: bool) -> Result<(), AccessError> {
        let gear = self.gears.get_mut(id).ok_or(AccessError::UnknownGear)?;
        if gear.present == present {
            return Ok(());
        }
        gear.present = present;
        if gear.phase == Phase::Releasing {
            return Ok(());
        }
        if !present && gear.lease.is_some() {
            gear.phase = Phase::Releasing;
            self.quiescent.remove(id);
        } else {
            self.activate(id);
        }
        Ok(())
    }
    /// 起動時だけ呼ぶ。lease / セッションは保存状態から復元しない。
    pub fn restore(&mut self, saved: &BTreeMap<String, Assignment>) {
        for (id, assignment) in saved {
            if let Some(gear) = self.gears.get_mut(id) {
                gear.assignment = assignment.clone();
                gear.lease = None;
                self.activate(id);
            }
        }
    }
    pub fn assignments(&self) -> BTreeMap<String, Assignment> {
        self.gears
            .iter()
            .map(|(id, gear)| (id.clone(), gear.assignment.clone()))
            .collect()
    }
    pub fn client_for_session(&self, session: &str) -> Option<&str> {
        self.sessions.get(session).map(String::as_str)
    }
    pub fn is_quiescent(&self, id: &str) -> bool {
        self.quiescent.contains(id)
    }
    pub fn epoch(&self) -> &str {
        &self.boot_id
    }
    fn activate(&mut self, id: &str) {
        let gear = self.gears.get_mut(id).expect("gear validated by caller");
        gear.lease = None;
        gear.phase = if gear.assignment.client_id.is_some() {
            Phase::Waiting
        } else {
            Phase::Off
        };
        if !gear.present {
            return;
        }
        let Some(session) = self
            .sessions
            .iter()
            .find(|(_, client)| Some(*client) == gear.assignment.client_id.as_ref())
            .map(|(session, _)| session.clone())
        else {
            return;
        };
        self.sequence += 1;
        gear.lease = Some(Lease {
            session_id: session,
            token: format!("{}:{}", self.boot_id, self.sequence),
        });
        gear.phase = Phase::Active;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rig() -> Broker {
        let mut b = Broker::new("test-boot");
        b.register_session("a1", "ladyland").unwrap();
        b.register_session("b1", "vp").unwrap();
        b.add_gear("nano-1", "nanokontrol", true);
        b.add_gear("lpd-1", "lpd8", true);
        b.add_gear("maru-1", "maru", true);
        b
    }

    #[test]
    fn enabling_one_gear_does_not_enable_the_other() {
        let mut b = rig();
        b.enable("nano-1", "a1", 0, false).unwrap();
        assert_eq!(b.gears["nano-1"].phase, Phase::Active);
        assert_eq!(b.gears["lpd-1"].phase, Phase::Off);
        assert_eq!(b.gears["maru-1"].phase, Phase::Off);
        assert_eq!(
            b.gears["nano-1"].assignment.client_id.as_deref(),
            Some("ladyland")
        );
    }

    #[test]
    fn repeated_discovery_does_not_reset_assignment_or_lease() {
        let mut b = rig();
        b.enable("nano-1", "a1", 0, false).unwrap();
        let before = b.gears["nano-1"].clone();
        b.add_gear("nano-1", "nanokontrol", true);
        assert_eq!(b.gears["nano-1"], before);
    }

    #[test]
    fn absent_gear_remembers_intent_without_claiming_active() {
        let mut b = rig();
        b.add_gear("fgdp-1", "fgdp", false);
        b.enable("fgdp-1", "a1", 0, false).unwrap();
        assert_eq!(b.gears["fgdp-1"].phase, Phase::Waiting);
        assert!(b.gears["fgdp-1"].lease.is_none());
    }

    #[test]
    fn handoff_requires_confirmation_and_two_sided_quiescence() {
        let mut b = rig();
        b.enable("maru-1", "a1", 0, false).unwrap();
        let old = b.gears["maru-1"].lease.clone().expect("old lease");
        assert_eq!(
            b.enable("maru-1", "b1", 1, false),
            Err(AccessError::Conflict)
        );
        b.enable("maru-1", "b1", 1, true).unwrap();
        assert_eq!(b.gears["maru-1"].phase, Phase::Releasing);
        assert_eq!(
            b.authorize_output("maru-1", "a1", &old.token),
            Err(AccessError::StaleLease)
        );
        assert_eq!(b.drained("maru-1"), Err(AccessError::Pending));
        b.quiesced("maru-1", "a1", &old.token).unwrap();
        b.drained("maru-1").unwrap();
        let next = b.gears["maru-1"].lease.clone().expect("successor lease");
        assert_eq!(next.session_id, "b1");
        assert_ne!(next.token, old.token);
        assert_eq!(
            b.authorize_output("maru-1", "a1", &old.token),
            Err(AccessError::StaleLease)
        );
        assert_eq!(b.authorize_output("maru-1", "b1", &next.token), Ok(()));
    }

    #[test]
    fn stale_confirmation_cannot_take_over_a_changed_gear() {
        let mut b = rig();
        b.enable("nano-1", "a1", 0, false).unwrap();
        assert_eq!(
            b.enable("nano-1", "b1", 0, true),
            Err(AccessError::StaleRevision)
        );
        assert_eq!(
            b.gears["nano-1"].assignment.client_id.as_deref(),
            Some("ladyland")
        );
    }

    #[test]
    fn disconnect_revokes_runtime_lease_but_retains_saved_assignment() {
        let mut b = rig();
        b.enable("nano-1", "a1", 0, false).unwrap();
        b.disconnect_session("a1");
        assert_eq!(b.gears["nano-1"].phase, Phase::Releasing);
        b.drained("nano-1").unwrap();
        assert_eq!(b.gears["nano-1"].phase, Phase::Waiting);
        assert_eq!(
            b.gears["nano-1"].assignment.client_id.as_deref(),
            Some("ladyland")
        );
    }

    #[test]
    fn off_survives_restart_and_hotplug() {
        let mut b = rig();
        b.enable("nano-1", "a1", 0, false).unwrap();
        let lease = b.gears["nano-1"].lease.clone().unwrap();
        b.disable("nano-1", "a1", 1).unwrap();
        b.quiesced("nano-1", "a1", &lease.token).unwrap();
        b.drained("nano-1").unwrap();
        let saved = b.assignments();
        assert_eq!(saved["nano-1"].revision, 2);
        let mut restored = rig();
        restored.restore(&saved);
        restored.set_present("nano-1", false).unwrap();
        restored.set_present("nano-1", true).unwrap();
        assert_eq!(restored.gears["nano-1"].assignment.revision, 2);
        assert_eq!(restored.gears["nano-1"].phase, Phase::Off);
        assert!(restored.gears["nano-1"].lease.is_none());
    }

    #[test]
    fn unplug_requests_cleanup_and_replug_gets_fresh_lease() {
        let mut b = rig();
        b.enable("nano-1", "a1", 0, false).unwrap();
        let old = b.gears["nano-1"].lease.clone().unwrap();
        b.set_present("nano-1", false).unwrap();
        assert_eq!(b.gears["nano-1"].phase, Phase::Releasing);
        b.quiesced("nano-1", "a1", &old.token).unwrap();
        b.drained("nano-1").unwrap();
        assert_eq!(b.gears["nano-1"].phase, Phase::Waiting);
        b.set_present("nano-1", true).unwrap();
        assert_eq!(b.gears["nano-1"].phase, Phase::Active);
        assert_ne!(b.gears["nano-1"].lease.as_ref().unwrap().token, old.token);
    }

    #[test]
    fn duplicate_session_or_client_and_pending_or_conflict_transitions_are_rejected() {
        let mut b = rig();
        assert_eq!(
            b.register_session("a1", "other"),
            Err(AccessError::AlreadyConnected)
        );
        assert_eq!(
            b.register_session("a2", "ladyland"),
            Err(AccessError::AlreadyConnected)
        );

        // Waiting の担当アプリが再接続したとき自動で Active に昇格する
        b.enable("maru-1", "a1", 0, false).unwrap();
        b.disconnect_session("a1");
        b.drained("maru-1").unwrap();
        assert_eq!(b.gears["maru-1"].phase, Phase::Waiting);
        b.register_session("a2", "ladyland").unwrap();
        assert_eq!(b.gears["maru-1"].phase, Phase::Active);
        assert_eq!(b.gears["maru-1"].lease.as_ref().unwrap().session_id, "a2");

        // 他アプリの disable は Conflict、Releasing 中の enable は Pending、新オーナーの disable で Off へ着地
        assert_eq!(b.disable("maru-1", "b1", 1), Err(AccessError::Conflict));
        let old_token = b.gears["maru-1"].lease.as_ref().unwrap().token.clone();
        b.enable("maru-1", "b1", 1, true).unwrap();
        assert_eq!(b.gears["maru-1"].phase, Phase::Releasing);
        assert_eq!(b.enable("maru-1", "a2", 2, true), Err(AccessError::Pending));
        b.disable("maru-1", "b1", 2).unwrap();
        b.quiesced("maru-1", "a2", &old_token).unwrap();
        b.drained("maru-1").unwrap();
        assert_eq!(b.gears["maru-1"].phase, Phase::Off);
        assert!(b.gears["maru-1"].assignment.client_id.is_none());
    }
}
