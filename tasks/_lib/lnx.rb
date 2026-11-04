# frozen_string_literal: true

# mise の file task（tasks/ 以下）が共有する道具。tasks/_lib はタスクとして扱われない。
require "json"
require "shellwords"

$stdout.sync = true # exec でプロセスが置き換わる前に出力を流す

module Lnx
  ROOT = ENV.fetch("MISE_PROJECT_ROOT") { File.expand_path("../..", __dir__) }
  IOS_DIR = File.join(ROOT, "apps", "ios")
  SERVER_CONFIG = File.join(ROOT, "crates", "lnx-server", "lnx-server.example.toml")
  SERVER_BIN = File.join(ROOT, "target", "debug", "lnx-server")
  APP_ID = "club.chronista.lnx.creare"
  # シミュレータは名前 + OS で選ぶ（同名の端末が runtime ごとにあるため）
  SIM_NAME = ENV.fetch("LNX_IOS_SIM", "iPad Pro 11-inch (M5)")
  SIM_OS = ENV.fetch("LNX_IOS_OS", "26.5")

  module_function

  # 見せてから走らせ、失敗したらそこで止まる
  def run(*cmd, chdir: ROOT)
    puts "$ #{cmd.shelljoin}"
    system(*cmd, chdir: chdir) or exit($?.exitstatus || 1)
  end

  # 常駐するものはプロセスごと置き換える（Ctrl-C がそのまま届く）
  def exec!(*cmd, chdir: ROOT)
    puts "$ #{cmd.shelljoin}"
    Dir.chdir(chdir)
    exec(*cmd)
  end

  # "[::]:12730" → 12730。port が無ければ nil
  def port_of(addr)
    port = addr[/:(\d+)\z/, 1]
    port && Integer(port)
  end

  # pid を管理している launchd のラベル（launchctl list の PID / Status / Label）。管理外なら nil
  def launchd_label(pid, listing = `launchctl list 2>/dev/null`)
    listing.each_line do |line|
      fields = line.chomp.split("\t")
      return fields[2] if fields.size == 3 && fields[0] == pid.to_s
    end
    nil
  end

  # UDP の port で待ち受けているプロセスを止める（TERM → 3 秒待って残れば KILL）。
  # 止めるのは lnx-server だけ。別のプロセスが握っていたら止めずに知らせて抜ける。
  # launchd の常駐（KeepAlive）は止めても立ち上がり直して取り合うので、止めずに案内して抜ける
  def stop_listeners(port)
    pids = listener_pids(port) - [Process.pid]
    return if pids.empty?

    pids.each do |pid|
      name = `ps -o comm= -p #{pid}`.strip
      unless File.basename(name) == "lnx-server"
        abort "port #{port} は #{name}（pid #{pid}）が使っている。lnx-server ではないので止めない"
      end
      if (label = launchd_label(pid))
        abort "port #{port} は LaunchAgent（#{label}）の lnx-server（pid #{pid}）が使っている。止めても立ち上がり直すので止めない。" \
              "LNX_SERVER_LABEL=#{label} で mise run server:restart か server:uninstall を使う"
      end
      puts "古い lnx-server（pid #{pid}）を止める"
      Process.kill("TERM", pid)
    end
    deadline = Time.now + 3
    sleep 0.1 while Time.now < deadline && pids.any? { |pid| alive?(pid) }
    pids.select { |pid| alive?(pid) }.each do |pid|
      puts "止まらないので KILL（pid #{pid}）"
      Process.kill("KILL", pid)
    end
  end

  # UDP の port で「待ち受けている」プロセス。相手が決まったソケット（"a->b"）はつながっているクライアント
  # （Mac 版 lnx creare など）なので除く。lsof -F の n 行がソケットの名前、p 行がプロセス
  def listener_pids(port)
    pids = []
    current = nil
    `lsof -nP -F pn -iUDP:#{port}`.each_line do |line|
      case line[0]
      when "p" then current = line[1..].to_i
      when "n" then pids << current if current && !line.include?("->")
      end
    end
    pids.uniq
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def simulator_udid
    devices = JSON.parse(`xcrun simctl list devices available -j`).fetch("devices")
    runtime = "iOS-#{SIM_OS.tr('.', '-')}"
    key = devices.keys.find { |k| k.end_with?(runtime) } or abort "iOS #{SIM_OS} のシミュレータ runtime が無い"
    device = devices[key].find { |d| d["name"] == SIM_NAME } or abort "#{SIM_NAME}（iOS #{SIM_OS}）が無い"
    device["udid"]
  end
end
