# frozen_string_literal: true

# server:ask — Bonjour の名乗りに答えているかを、NIC ごとに IPv4 / IPv6 で直接問う（legacy unicast:
# エフェメラルな port から 224.0.0.251 / ff02::fb へ SRV を問い、サーバの生の応答を受ける）。
# 同じ Mac の dns-sd -L / -G は mDNSResponder のキャッシュの見え方で当てにならない
# （docs/design/01-lnx-server-link.md「事故のときログで何を見るか」）。macOS 付属の Ruby（2.6）でも動く書き方にする
require "socket"
require "ipaddr"

module Lnx
  module MdnsAsk
    GROUP_V4 = "224.0.0.251"
    GROUP_V6 = "ff02::fb"
    PORT = 5353
    SRV = 33

    # getifaddrs の 1 行（family は :inet / :inet6。multicast は「名乗りに関係する NIC か」）
    Entry = Struct.new(:name, :family, :address, :index, :multicast)
    # 問う先の NIC（IPv4 は問いの出口にするアドレス、IPv6 は NIC の番号）
    Nic = Struct.new(:name, :ipv4, :ipv6_index)

    module_function

    def query(name, id, qtype = SRV)
      labels = name.chomp(".").split(".").map { |l| [l.bytesize].pack("C") + l.b }
      [id, 0, 1, 0, 0, 0].pack("n6") + labels.join + "\x00".b + [qtype, 1].pack("n2")
    end

    # 応答の答えの数。自分の問い（id）への応答でなければ nil
    def answer_count(packet, id)
      return nil if packet.bytesize < 12

      rid, _flags, _questions, answers = packet.unpack("n4")
      rid == id ? answers : nil
    end

    # 名乗りに関係する NIC（UP で MULTICAST、point-to-point と Apple の p2p（awdl / llw）は除く）
    def interfaces(entries = system_entries)
      nics = {}
      entries.each do |e|
        next unless e.multicast
        next if e.name.start_with?("awdl", "llw")

        nic = (nics[e.name] ||= Nic.new(e.name, nil, nil))
        if e.family == :inet
          nic.ipv4 ||= e.address
        else
          nic.ipv6_index ||= e.index
        end
      end
      nics.values.select { |n| n.ipv4 || n.ipv6_index }
    end

    def system_entries
      Socket.getifaddrs.map do |ifa|
        addr = ifa.addr
        next unless addr && addr.ip?

        flags = ifa.flags
        multicast = (flags & Socket::IFF_UP) != 0 && (flags & Socket::IFF_MULTICAST) != 0 &&
                    (flags & Socket::IFF_POINTOPOINT).zero?
        Entry.new(ifa.name, addr.ipv4? ? :inet : :inet6, addr.ip_address, ifa.ifindex, multicast)
      end.compact
    end

    # 設定ファイル（一段目）の name。無ければ nil
    def name_from_config(path)
      return nil unless File.exist?(path)

      File.foreach(path) do |line|
        break if line.start_with?("[") # [[servers]] より後は既知サーバの name

        m = line.match(/\Aname\s*=\s*"([^"]+)"/)
        return m[1] if m
      end
      nil
    end

    def ask_v4(name, nic, timeout: 2.0)
      sock = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM, 0)
      sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF, IPAddr.new(nic.ipv4).hton)
      sock.bind(Addrinfo.udp(nic.ipv4, 0))
      ask(sock, name, Addrinfo.udp(GROUP_V4, PORT), timeout)
    ensure
      sock&.close
    end

    def ask_v6(name, nic, timeout: 2.0)
      sock = Socket.new(Socket::AF_INET6, Socket::SOCK_DGRAM, 0)
      sock.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_MULTICAST_IF, [nic.ipv6_index].pack("I"))
      sock.bind(Addrinfo.udp("::", 0))
      ask(sock, name, Addrinfo.udp("#{GROUP_V6}%#{nic.name}", PORT), timeout)
    ensure
      sock&.close
    end

    # 問って、締め切りまでに来た自分宛ての応答の送り手を返す（答えの数が 1 以上のもの）
    def ask(sock, name, dest, timeout)
      id = rand(1..0xffff)
      sock.send(query(name, id), 0, dest)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      got = []
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break if remaining <= 0
        break unless IO.select([sock], nil, nil, remaining)

        data, from = sock.recvfrom(9000)
        answers = answer_count(data, id)
        got << from.ip_address if answers && answers.positive?
      end
      got.uniq
    end
  end
end
