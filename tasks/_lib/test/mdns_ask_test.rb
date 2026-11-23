# frozen_string_literal: true

# server:ask の組み立て（Lnx::MdnsAsk）のテスト。ネットワークに触る部分（ask_v4 / ask_v6）は含めない
require "minitest/autorun"
require "tmpdir"
require_relative "../mdns_ask"

class MdnsAskPacketTest < Minitest::Test
  def test_srv_の問い合わせを組む
    packet = Lnx::MdnsAsk.query("lnx-mac._lnx._udp.local.", 0x1234)
    header = packet[0, 12].unpack("n6")
    assert_equal [0x1234, 0, 1, 0, 0, 0], header
    name = "\x07lnx-mac\x04_lnx\x04_udp\x05local\x00".b
    assert_equal name, packet[12, name.bytesize]
    assert_equal [33, 1], packet[12 + name.bytesize, 4].unpack("n2") # SRV、IN（QU ではない）
  end

  def test_応答の答えの数を読む
    reply = [0x1234, 0x8400, 0, 2, 0, 1].pack("n6")
    assert_equal 2, Lnx::MdnsAsk.answer_count(reply, 0x1234)
    assert_nil Lnx::MdnsAsk.answer_count(reply, 0x9999), "id が違えば自分宛てではない"
    assert_nil Lnx::MdnsAsk.answer_count("\x00".b, 0x1234), "短すぎる"
  end
end

class MdnsAskInterfacesTest < Minitest::Test
  Entry = Lnx::MdnsAsk::Entry

  def test_nic_ごとに_ipv4_と_ipv6_をまとめる
    entries = [
      Entry.new("lo0", :inet, "127.0.0.1", 1, true),
      Entry.new("lo0", :inet6, "::1", 1, true),
      Entry.new("en0", :inet, "192.168.68.117", 13, true),
      Entry.new("en0", :inet6, "fe80::14cc:ea42:a65b:ae49%en0", 13, true),
      Entry.new("bridge100", :inet, "192.168.234.1", 27, true),
      Entry.new("utun4", :inet, "100.71.138.86", 28, false), # point-to-point は名乗りに関係しない
      Entry.new("awdl0", :inet6, "fe80::1%awdl0", 14, true),
      Entry.new("llw0", :inet6, "fe80::2%llw0", 15, true)
    ]
    nics = Lnx::MdnsAsk.interfaces(entries)
    assert_equal %w[lo0 en0 bridge100], nics.map(&:name)
    en0 = nics.find { |n| n.name == "en0" }
    assert_equal "192.168.68.117", en0.ipv4
    assert_equal 13, en0.ipv6_index
    assert_nil nics.find { |n| n.name == "bridge100" }.ipv6_index, "IPv6 が無ければ問わない"
  end
end

class MdnsAskNameTest < Minitest::Test
  def test_設定ファイルから名乗りを読む
    Dir.mktmpdir do |dir|
      path = File.join(dir, "lnx-server.toml")
      File.write(path, "# lnx-server の設定\nname = \"lnx-mac\"\n\n[[servers]]\nname = \"Ladyland Field\"\n")
      assert_equal "lnx-mac", Lnx::MdnsAsk.name_from_config(path), "[[servers]] の name ではなく一段目の name"
      assert_nil Lnx::MdnsAsk.name_from_config(File.join(dir, "none.toml"))
    end
  end
end
