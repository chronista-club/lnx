# frozen_string_literal: true

# LNX サーバを launchd のユーザー LaunchAgent で常駐させる道具（server:install / uninstall / restart / logs / status）。
# 置き場はラベルから決める。試験用のラベル（既定以外）は、port・名乗り・証明書の置き場も本番と分けないと install が断る。
# macOS 付属の Ruby（2.6）でも動く書き方にする（mise は Ruby を入れていない）
require "fileutils"
require "json"
require "shellwords"
require_relative "lnx"

module Lnx
  module Agent
    DEFAULT_LABEL = "club.chronista.lnx-server"
    DEFAULT_ADDR = "[::]:12730"
    DEFAULT_LOCAL_ADDR = "[::1]:12731"
    # lnx-server の既定の証明書の置き場（identity::default_dir と同じ）。設定ファイルもここに置く
    SUPPORT_DIR = "Library/Application Support/club.chronista.lnx-server"

    # install のときに決まる一式。plist の中身はここから作る
    Settings = Struct.new(:label, :home, :addr, :local_addr, :state_dir, :config, :name, :no_mdns, keyword_init: true) do
      def self.from_env(env = ENV, home: Dir.home)
        new(
          label: env.fetch("LNX_SERVER_LABEL", DEFAULT_LABEL),
          home: home,
          addr: env.fetch("LNX_SERVER_ADDR", DEFAULT_ADDR),
          local_addr: env.fetch("LNX_SERVER_LOCAL_ADDR", DEFAULT_LOCAL_ADDR),
          state_dir: env["LNX_SERVER_STATE"],
          config: env["LNX_SERVER_CONFIG"],
          name: env["LNX_SERVER_NAME"],
          no_mdns: env["LNX_SERVER_NO_MDNS"] == "1"
        )
      end

      def production?
        label == DEFAULT_LABEL
      end

      # 置き場の名前（club.chronista.lnx-server → lnx-server、試験用 .test → lnx-server.test）
      def short_name
        label.delete_prefix("club.chronista.")
      end

      def plist_path
        File.join(home, "Library", "LaunchAgents", "#{label}.plist")
      end

      # target/ はビルドのたびに変わり、mbx では symlink の先にある。常駐はコピーを指す
      def bin_path
        File.join(home, ".local", "share", short_name, "bin", "lnx-server")
      end

      def log_path
        File.join(home, "Library", "Logs", "#{short_name}.log")
      end

      def config_path
        config || File.join(state_dir || File.join(home, SUPPORT_DIR), "lnx-server.toml")
      end

      def port
        Lnx.port_of(addr) or abort "LNX_SERVER_ADDR（#{addr}）に port が無い（例 [::]:12730）"
      end

      def local_port
        Lnx.port_of(local_addr) or abort "LNX_SERVER_LOCAL_ADDR（#{local_addr}）に port が無い（例 [::1]:12731）"
      end

      def service
        "gui/#{Process.uid}/#{label}"
      end

      def program_arguments
        args = [bin_path, "--addr", addr, "--local-addr", local_addr, "--config", config_path]
        args += ["--state-dir", state_dir] if state_dir
        args += ["--name", name] if name
        args << "--no-mdns" if no_mdns
        args
      end
    end

    module_function

    # 試験用ラベルが本番に触れる組み合わせ。空なら install してよい。
    # env を一つ落とすと本番の port を取り合い（stop_listeners が本番を止める）、lnx-mac を名乗って goodbye で本物の記録を消す
    def isolation_problems(settings)
      return [] if settings.production?

      found = []
      found << "port #{settings.port} は本番の待ち受け。LNX_SERVER_ADDR を別の port に" if settings.port == Lnx.port_of(DEFAULT_ADDR)
      if settings.local_port == Lnx.port_of(DEFAULT_LOCAL_ADDR)
        found << "port #{settings.local_port} は本番の手元用。LNX_SERVER_LOCAL_ADDR を別の port に"
      end
      unless settings.name || settings.no_mdns
        found << "本番と同じ名前で Bonjour に名乗ってしまう。LNX_SERVER_NAME を別の名前にするか LNX_SERVER_NO_MDNS=1"
      end
      found << "証明書と設定が本番の置き場になる。LNX_SERVER_STATE で分ける" unless settings.state_dir
      found
    end

    def plist(settings)
      args = settings.program_arguments.map { |a| "    <string>#{escape(a)}</string>" }.join("\n")
      log = escape(settings.log_path)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>#{escape(settings.label)}</string>
          <key>ProgramArguments</key>
          <array>
        #{args}
          </array>
          <key>EnvironmentVariables</key>
          <dict>
            <key>RUST_LOG</key>
            <string>info</string>
            <key>RUST_BACKTRACE</key>
            <string>1</string>
          </dict>
          <key>WorkingDirectory</key>
          <string>#{escape(File.dirname(settings.bin_path))}</string>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>#{log}</string>
          <key>StandardErrorPath</key>
          <string>#{log}</string>
        </dict>
        </plist>
      XML
    end

    def escape(text)
      text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    # plist が置いてあれば「入っている」（launchd に載っているかは loaded? で見る）
    def installed?(settings)
      File.exist?(settings.plist_path)
    end

    # 入っている plist の ProgramArguments。restart / status / uninstall は env ではなくこれを正にする
    # （install のときの env で走っている。今の env が違っても見誤らない）。無い・読めなければ nil（落ちずに先へ進める）
    def installed_args(settings)
      return nil unless installed?(settings)

      json = IO.popen(["plutil", "-extract", "ProgramArguments", "json", "-o", "-", settings.plist_path],
                      err: File::NULL, &:read)
      args = $?.success? ? JSON.parse(json) : nil
      return args if args.is_a?(Array)

      warn "plist の ProgramArguments を読めない: #{settings.plist_path}"
      nil
    rescue JSON::ParserError
      warn "plist の ProgramArguments を読めない: #{settings.plist_path}"
      nil
    end

    def arg_value(args, flag)
      index = args && args.index(flag)
      index && args[index + 1]
    end

    # 入っている plist の --addr / --local-addr の port。どちらかが読めなければ nil（呼び手は env に戻る）
    def installed_ports(settings)
      args = installed_args(settings) or return nil
      ports = %w[--addr --local-addr].map do |flag|
        value = arg_value(args, flag)
        value && Lnx.port_of(value)
      end
      ports.all? ? ports : nil
    end

    def loaded?(settings)
      system("launchctl", "print", settings.service, out: File::NULL, err: File::NULL)
    end

    # SMAppService が載せたジョブを launchctl print で見たときの持ち主
    SERVICE_MANAGEMENT = "com.apple.xpc.ServiceManagement"

    # Mac 版 lnx creare（メニューバー）が SMAppService で載せたジョブ。このタスクたちは降ろしも差し替えもしない。
    # 持ち主は launchd に聞く（plist の有無では決めない。#38 の plist が残っていても、消えていても取り違えない）
    def app_managed?(settings, state: state(settings))
      !state.nil? && state[:managed_by] == SERVICE_MANAGEMENT
    end

    def app_managed_message(settings)
      "LNX サーバは Mac 版 lnx creare（メニューバー）が SMAppService で常駐させている（#{settings.label}）。" \
        "開始・停止・再起動はメニューから。このタスクでは触らない"
    end

    # launchctl print の要るところだけ（state / pid / 起動回数 / 前の終わり方）
    def state(settings)
      out = `launchctl print #{settings.service.shellescape} 2>/dev/null`
      return nil unless $?.success?

      parse_state(out)
    end

    # 見るのは一段目（タブ 1 つ）の行だけ。endpoints などの入れ子にも state がある。
    # 前の終わり方は、exit なら "last exit code"、シグナルなら "last terminating signal" に出る。
    # SMAppService が載せたジョブには managed_by と parent bundle identifier（載せたアプリ）が出る
    def parse_state(out)
      {
        state: out[/^\tstate = (.+)$/, 1],
        pid: out[/^\tpid = (\d+)$/, 1]&.to_i,
        runs: out[/^\truns = (\d+)$/, 1]&.to_i,
        last_exit: out[/^\tlast terminating signal = (.+)$/, 1] || out[/^\tlast exit code = (.+)$/, 1],
        managed_by: out[/^\tmanaged_by = (.+)$/, 1],
        parent_bundle: out[/^\tparent bundle identifier = (.+)$/, 1]
      }
    end

    # 走っている実行ファイルを壊さないよう、隣に書いてから rename で差し替える
    def install_binary(source, settings)
      FileUtils.mkdir_p(File.dirname(settings.bin_path))
      staging = "#{settings.bin_path}.new"
      FileUtils.cp(source, staging)
      File.chmod(0o755, staging)
      File.rename(staging, settings.bin_path)
    end

    # 設定ファイルが無ければ example から写す（あれば触らない。手で直した一覧を消さない）
    def seed_config(example, settings)
      return false if File.exist?(settings.config_path)

      FileUtils.mkdir_p(File.dirname(settings.config_path))
      FileUtils.cp(example, settings.config_path)
      true
    end

    # lint が通らなければ置かない（壊れた plist を残すと server:run が止まり続ける）
    def write_plist(settings)
      FileUtils.mkdir_p(File.dirname(settings.plist_path))
      staging = "#{settings.plist_path}.new"
      File.write(staging, plist(settings))
      unless system("plutil", "-lint", "-s", staging)
        FileUtils.rm_f(staging)
        abort "plist を組めない（plutil -lint が通らない）: #{settings.plist_path}"
      end
      File.rename(staging, settings.plist_path)
    end

    # 走り出して pid が付くまで待つ。来なければ nil
    def wait_running(settings, timeout: 10)
      deadline = Time.now + timeout
      while Time.now < deadline
        s = state(settings)
        return s if s && s[:state] == "running" && s[:pid]

        sleep 0.2
      end
      nil
    end

    # launchd から降ろし、消えるまで待つ。降りなければ止まる（KeepAlive で走り続けているのに「降ろした」と言わない）
    def bootout(settings)
      return unless loaded?(settings)

      system("launchctl", "bootout", settings.service)
      deadline = Time.now + 10
      sleep 0.2 while Time.now < deadline && loaded?(settings)
      return unless loaded?(settings)

      abort "launchd から降ろせない（#{settings.label}）。mise run server:status で様子を見る"
    end

    # pid が port で待ち受けるまで待つ（launchd の running は「起動した」だけで、待ち受けまでは見ない）
    def wait_listening(port, pid, timeout: 10)
      deadline = Time.now + timeout
      while Time.now < deadline
        return true if Lnx.listener_pids(port).include?(pid)

        sleep 0.2
      end
      false
    end

    # 立ち上がって待ち受けるまで見届ける。前の pid（restart）とは別の pid を待つ
    def confirm_running(settings, previous_pid: nil)
      deadline = Time.now + 15
      running = nil
      while Time.now < deadline
        running = wait_running(settings, timeout: 1)
        break if running && running[:pid] != previous_pid

        running = nil
      end
      running or abort "立ち上がらない（#{settings.label}）。ログの最後:\n#{tail(settings)}"
      port, = installed_ports(settings) || [settings.port]
      wait_listening(port, running[:pid]) or
        abort "pid #{running[:pid]} が port #{port} で待ち受けない。ログの最後:\n#{tail(settings)}"
      puts "常駐中: #{settings.label}（pid #{running[:pid]}、port #{port}）"
      puts "ログ: #{settings.log_path}（mise run server:logs）"
    end

    def tail(settings, lines = 20)
      return "（ログはまだ無い: #{settings.log_path}）" unless File.exist?(settings.log_path)

      File.readlines(settings.log_path).last(lines).join
    end
  end
end
