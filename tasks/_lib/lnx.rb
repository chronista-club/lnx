# frozen_string_literal: true

# mise の file task（tasks/ 以下）が共有する道具。tasks/_lib はタスクとして扱われない。
require "json"
require "shellwords"

$stdout.sync = true # exec でプロセスが置き換わる前に出力を流す

module Lnx
  ROOT = ENV.fetch("MISE_PROJECT_ROOT") { File.expand_path("../..", __dir__) }
  IOS_DIR = File.join(ROOT, "apps", "ios")
  SERVER_CONFIG = File.join(ROOT, "crates", "lnx-server", "lnx-server.example.toml")
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

  # UDP の port で待ち受けているプロセスを止める（TERM → 3 秒待って残れば KILL）。
  # 止めるのは lnx-server だけ。別のプロセスが握っていたら止めずに知らせて抜ける
  def stop_listeners(port)
    pids = `lsof -nP -t -iUDP:#{port}`.split.map(&:to_i).uniq - [Process.pid]
    return if pids.empty?

    pids.each do |pid|
      name = `ps -o comm= -p #{pid}`.strip
      unless File.basename(name) == "lnx-server"
        abort "port #{port} は #{name}（pid #{pid}）が使っている。lnx-server ではないので止めない"
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
