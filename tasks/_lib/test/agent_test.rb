# frozen_string_literal: true

# server:install などが使う LaunchAgent の組み立て（Lnx::Agent）のテスト。
# `mise run server:test` が cargo test のあとに走らせる（単体なら `ruby tasks/_lib/test/agent_test.rb`）
require "minitest/autorun"
require "tmpdir"
require_relative "../agent"

class AgentSettingsTest < Minitest::Test
  HOME = "/Users/someone"
  SUPPORT = "#{HOME}/Library/Application Support/club.chronista.lnx-server".freeze

  def settings(env = {})
    Lnx::Agent::Settings.from_env(env, home: HOME)
  end

  def test_既定のラベルと置き場
    s = settings
    assert_equal "club.chronista.lnx-server", s.label
    assert_equal "#{HOME}/Library/LaunchAgents/club.chronista.lnx-server.plist", s.plist_path
    assert_equal "#{HOME}/.local/share/lnx-server/bin/lnx-server", s.bin_path
    assert_equal "#{HOME}/Library/Logs/lnx-server.log", s.log_path
    assert_equal "#{SUPPORT}/lnx-server.toml", s.config_path
    assert_equal 12730, s.port
  end

  def test_既定の引数は証明書の置き場を渡さない
    # 証明書は lnx-server の既定の置き場（server:run と同じ）を使い続ける。ペアリング済みの pin を外さない
    assert_equal [
      "#{HOME}/.local/share/lnx-server/bin/lnx-server",
      "--addr", "[::]:12730",
      "--local-addr", "[::1]:12731",
      "--config", "#{SUPPORT}/lnx-server.toml"
    ], settings.program_arguments
  end

  def test_試験用のラベルは置き場が全部べつになる
    s = settings("LNX_SERVER_LABEL" => "club.chronista.lnx-server.test")
    assert_equal "#{HOME}/Library/LaunchAgents/club.chronista.lnx-server.test.plist", s.plist_path
    assert_equal "#{HOME}/.local/share/lnx-server.test/bin/lnx-server", s.bin_path
    assert_equal "#{HOME}/Library/Logs/lnx-server.test.log", s.log_path
  end

  def test_環境変数で引数を変えられる
    s = settings(
      "LNX_SERVER_ADDR" => "[::]:12740",
      "LNX_SERVER_LOCAL_ADDR" => "[::1]:12741",
      "LNX_SERVER_STATE" => "/tmp/lnx-state",
      "LNX_SERVER_NAME" => "lnx-agent-test",
      "LNX_SERVER_NO_MDNS" => "1"
    )
    assert_equal 12740, s.port
    assert_equal "/tmp/lnx-state/lnx-server.toml", s.config_path
    args = s.program_arguments
    assert_equal ["--addr", "[::]:12740"], args[1, 2]
    assert_equal ["--local-addr", "[::1]:12741"], args[3, 2]
    assert_includes args.each_cons(2).to_a, ["--state-dir", "/tmp/lnx-state"]
    assert_includes args.each_cons(2).to_a, ["--name", "lnx-agent-test"]
    assert_includes args, "--no-mdns"
  end

  def test_設定ファイルを直に指せる
    s = settings("LNX_SERVER_CONFIG" => "/etc/lnx/my.toml")
    assert_equal "/etc/lnx/my.toml", s.config_path
  end
end

class AgentIsolationTest < Minitest::Test
  TEST = "club.chronista.lnx-server.test"

  def problems(env)
    Lnx::Agent.isolation_problems(Lnx::Agent::Settings.from_env(env, home: "/Users/someone"))
  end

  def test_本番のラベルは何も言わない
    assert_empty problems({})
  end

  # 試験用ラベルは置き場だけでなく、port・名乗り・証明書も本番と分ける（env を一つ落としても本番に触れない）
  def test_試験用ラベルで本番の_port_名乗り_証明書を使うと断る
    found = problems("LNX_SERVER_LABEL" => TEST)
    assert_equal 4, found.size, found.join(" / ")
    assert(found.any? { |m| m.include?("12730") })
    assert(found.any? { |m| m.include?("12731") })
    assert(found.any? { |m| m.include?("LNX_SERVER_NAME") })
    assert(found.any? { |m| m.include?("LNX_SERVER_STATE") })
  end

  def test_試験用ラベルで全部分ければ通る
    assert_empty problems(
      "LNX_SERVER_LABEL" => TEST, "LNX_SERVER_ADDR" => "[::]:12740", "LNX_SERVER_LOCAL_ADDR" => "[::1]:12741",
      "LNX_SERVER_STATE" => "/tmp/lnx-agent-test", "LNX_SERVER_NO_MDNS" => "1"
    )
  end
end

class PortTest < Minitest::Test
  def test_アドレスから_port_を取る
    assert_equal 12730, Lnx.port_of("[::]:12730")
    assert_equal 12731, Lnx.port_of("[::1]:12731")
    assert_nil Lnx.port_of("[::]")
  end
end

class LaunchdLabelTest < Minitest::Test
  # launchctl list の形（PID / Status / Label のタブ区切り。走っていなければ PID は "-"）
  LIST = "PID\tStatus\tLabel\n-\t0\tcom.apple.x\n36821\t0\tclub.chronista.lnx-server.test\n512\t-9\tcom.example.y\n"

  def test_pid_を管理している_launchd_のラベルを引く
    assert_equal "club.chronista.lnx-server.test", Lnx.launchd_label(36821, LIST)
    assert_nil Lnx.launchd_label(4242, LIST)
  end
end

class AgentPlistTest < Minitest::Test
  def settings(env = {})
    Lnx::Agent::Settings.from_env(env, home: "/Users/a&b")
  end

  def test_plist_は常駐の鍵を持つ
    xml = Lnx::Agent.plist(settings)
    assert_includes xml, "<key>Label</key>\n  <string>club.chronista.lnx-server</string>"
    assert_match %r{<key>RunAtLoad</key>\s*<true/>}, xml
    assert_match %r{<key>KeepAlive</key>\s*<true/>}, xml
    assert_match %r{<key>StandardOutPath</key>\s*<string>/Users/a&amp;b/Library/Logs/lnx-server.log</string>}, xml
    assert_match %r{<key>StandardErrorPath</key>\s*<string>/Users/a&amp;b/Library/Logs/lnx-server.log</string>}, xml
    # launchd は mise の env を持たない
    assert_match %r{<key>RUST_LOG</key>\s*<string>info</string>}, xml
  end

  def test_plist_の引数は順番どおりで_xml_の特殊文字を逃がす
    xml = Lnx::Agent.plist(settings)
    strings = xml[%r{<key>ProgramArguments</key>\s*<array>(.*?)</array>}m, 1].scan(%r{<string>(.*?)</string>}).flatten
    assert_equal settings.program_arguments.map { |a| a.gsub("&", "&amp;") }, strings
  end

  def test_plist_は_plutil_が読める
    skip "plutil が無い" unless system("which plutil", out: File::NULL)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "agent.plist")
      File.write(path, Lnx::Agent.plist(settings("LNX_SERVER_NAME" => "<lnx>")))
      assert system("plutil", "-lint", "-s", path), "plutil -lint が通らない"
    end
  end
end

class AgentStateTest < Minitest::Test
  # launchctl print gui/<uid>/<label> の抜粋（2026-11-04 に試験用ラベルで取った形）
  KILLED = "gui/501/club.chronista.lnx-server.test = {\n\tactive count = 1\n\tstate = running\n\n" \
           "\truns = 3\n\tpid = 36821\n\tlast terminating signal = Killed: 9\n" \
           "\tendpoints = {\n\t\t\"x\" = {\n\t\t\tport = 0\n\t\t\tstate = active\n\t\t}\n\t}\n}\n"
  EXITED = "gui/501/x = {\n\tstate = not running\n\truns = 1\n\tlast exit code = 1\n}\n"

  def test_走っていてシグナルで落ちたことがある
    assert_equal({ state: "running", pid: 36821, runs: 3, last_exit: "Killed: 9", managed_by: nil, parent_bundle: nil },
                 Lnx::Agent.parse_state(KILLED))
  end

  def test_止まっていて_exit_で抜けた
    assert_equal({ state: "not running", pid: nil, runs: 1, last_exit: "1", managed_by: nil, parent_bundle: nil },
                 Lnx::Agent.parse_state(EXITED))
  end
end

class AgentAppManagedTest < Minitest::Test
  # launchctl print の抜粋（2026-11-05 にこの Mac で読み取り。SMAppService の midistaged と、#38 の plist から載せたもの）
  SMAPP = "gui/501/club.chronista.lnx-server = {\n\tactive count = 1\n\tpath = (submitted by smd.353)\n" \
          "\tmanaged_by = com.apple.xpc.ServiceManagement\n\tstate = running\n\n" \
          "\tparent bundle identifier = club.chronista.lnx.creare\n\truns = 1\n\tpid = 69784\n}\n"
  PLIST = "gui/501/club.chronista.lnx-server = {\n\tactive count = 1\n" \
          "\tpath = /Users/someone/Library/LaunchAgents/club.chronista.lnx-server.plist\n" \
          "\tstate = running\n\truns = 1\n\tpid = 100\n}\n"

  def test_parse_state_は持ち主を読む
    st = Lnx::Agent.parse_state(SMAPP)
    assert_equal "com.apple.xpc.ServiceManagement", st[:managed_by]
    assert_equal "club.chronista.lnx.creare", st[:parent_bundle]
    assert_nil Lnx::Agent.parse_state(PLIST)[:managed_by]
  end

  # 持ち主は launchd に聞く。plist の有無では決めない（#38 の plist が残っていても、消えていても取り違えない）
  def test_launchd_の持ち主が_ServiceManagement_ならアプリのジョブ
    Dir.mktmpdir do |home|
      s = Lnx::Agent::Settings.from_env({}, home: home)
      assert Lnx::Agent.app_managed?(s, state: Lnx::Agent.parse_state(SMAPP))
      refute Lnx::Agent.app_managed?(s, state: Lnx::Agent.parse_state(PLIST)), "plist が無くても #38 のもの"
      refute Lnx::Agent.app_managed?(s, state: nil)

      FileUtils.mkdir_p(File.dirname(s.plist_path))
      File.write(s.plist_path, Lnx::Agent.plist(s))
      assert Lnx::Agent.app_managed?(s, state: Lnx::Agent.parse_state(SMAPP)), "plist が残っていてもアプリのもの"
    end
  end

  def test_案内はメニューを指す
    s = Lnx::Agent::Settings.from_env({}, home: "/Users/someone")
    message = Lnx::Agent.app_managed_message(s)
    assert_includes message, "club.chronista.lnx-server"
    assert_includes message, "メニュー"
  end
end

class AgentInstalledTest < Minitest::Test
  # restart / status は env ではなく、入っている plist の引数を正にする（install のときの port で走っている）
  def test_入っている_plist_から待ち受けの_port_を読む
    skip "plutil が無い" unless system("which plutil", out: File::NULL)
    Dir.mktmpdir do |home|
      installed = Lnx::Agent::Settings.from_env(
        { "LNX_SERVER_ADDR" => "[::]:12740", "LNX_SERVER_LOCAL_ADDR" => "[::1]:12741" }, home: home
      )
      FileUtils.mkdir_p(File.dirname(installed.plist_path))
      File.write(installed.plist_path, Lnx::Agent.plist(installed))

      now = Lnx::Agent::Settings.from_env({}, home: home) # 今の env は既定（12730）
      assert_equal [12740, 12741], Lnx::Agent.installed_ports(now)
    end
  end

  def test_入っている_plist_から設定ファイルの場所を読む
    skip "plutil が無い" unless system("which plutil", out: File::NULL)
    Dir.mktmpdir do |home|
      installed = Lnx::Agent::Settings.from_env({ "LNX_SERVER_STATE" => "/tmp/lnx-state" }, home: home)
      FileUtils.mkdir_p(File.dirname(installed.plist_path))
      File.write(installed.plist_path, Lnx::Agent.plist(installed))

      now = Lnx::Agent::Settings.from_env({}, home: home)
      assert_equal "/tmp/lnx-state/lnx-server.toml", Lnx::Agent.arg_value(Lnx::Agent.installed_args(now), "--config")
    end
  end

  def test_plist_が無ければ_port_は無い
    Dir.mktmpdir do |home|
      assert_nil Lnx::Agent.installed_ports(Lnx::Agent::Settings.from_env({}, home: home))
    end
  end

  # 壊れた plist でも uninstall まで進めるよう、読めなければ nil（例外で落ちない）
  def test_壊れた_plist_や引数の欠けた_plist_では_nil
    skip "plutil が無い" unless system("which plutil", out: File::NULL)
    Dir.mktmpdir do |home|
      s = Lnx::Agent::Settings.from_env({}, home: home)
      FileUtils.mkdir_p(File.dirname(s.plist_path))

      File.write(s.plist_path, "not a plist")
      _out, err = capture_io { assert_nil Lnx::Agent.installed_args(s) }
      assert_includes err, "読めない"
      capture_io { assert_nil Lnx::Agent.installed_ports(s) }

      lacking = Lnx::Agent.plist(s).sub(%r{\s*<string>--local-addr</string>\s*<string>\[::1\]:12731</string>}, "")
      File.write(s.plist_path, lacking)
      assert_nil Lnx::Agent.installed_ports(s)
    end
  end

  def test_plist_があれば入っているとみなす
    Dir.mktmpdir do |home|
      s = Lnx::Agent::Settings.from_env({}, home: home)
      refute Lnx::Agent.installed?(s)
      FileUtils.mkdir_p(File.dirname(s.plist_path))
      File.write(s.plist_path, Lnx::Agent.plist(s))
      assert Lnx::Agent.installed?(s)
    end
  end
end
