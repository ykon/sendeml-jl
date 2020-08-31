#=
    Copyright (c) Yuki Ono.
    Licensed under the MIT License.
=#

using SendEML
using Test

function make_simple_mail_text()::String
    text = """From: a001 <a001@ah62.example.jp>
Subject: test
To: a002@ah62.example.jp
Message-ID: <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>
Date: Sun, 26 Jul 2020 22:01:37 +0900
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:78.0) Gecko/20100101
 Thunderbird/78.0.1
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8; format=flowed
Content-Transfer-Encoding: 7bit
Content-Language: en-US

test"""
    replace(text, "\n" => "\r\n")
end

function make_folded_mail()::Vector{UInt8}
    text = """From: a001 <a001@ah62.example.jp>
Subject: test
To: a002@ah62.example.jp
Message-ID:
 <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>
Date:
 Sun, 26 Jul 2020
 22:01:37 +0900
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:78.0) Gecko/20100101
 Thunderbird/78.0.1
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8; format=flowed
Content-Transfer-Encoding: 7bit
Content-Language: en-US

test"""
    Vector{UInt8}(replace(text, "\n" => "\r\n"))
end

function make_folded_end_date()::Vector{UInt8}
    text = """From: a001 <a001@ah62.example.jp>
Subject: test
To: a002@ah62.example.jp
Message-ID:
 <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:78.0) Gecko/20100101
 Thunderbird/78.0.1
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8; format=flowed
Content-Transfer-Encoding: 7bit
Content-Language: en-US
Date:
 Sun, 26 Jul 2020
 22:01:37 +0900
"""
    Vector{UInt8}(replace(text, "\n" => "\r\n"))
end

function make_folded_end_message_id()::Vector{UInt8}
    text = """From: a001 <a001@ah62.example.jp>
Subject: test
To: a002@ah62.example.jp
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:78.0) Gecko/20100101
 Thunderbird/78.0.1
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8; format=flowed
Content-Transfer-Encoding: 7bit
Content-Language: en-US
Date:
 Sun, 26 Jul 2020
 22:01:37 +0900
Message-ID:
 <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>
"""
    Vector{UInt8}(replace(text, "\n" => "\r\n"))
end

function make_simple_mail()::Vector{UInt8}
    Vector{UInt8}(make_simple_mail_text())
end

function make_invalid_mail()::Vector{UInt8}
    Vector{UInt8}(replace(make_simple_mail_text(), "\r\n\r\n" => ""))
end

function make_test_send_cmd(expected::String)::Function
    cmd -> begin
        @test expected == cmd
        cmd
    end
end

# ! Avoid String(): -> String(copy())
# String constructor truncates data. #32528
# https://github.com/JuliaLang/julia/issues/32528

function get_header_line(header::Vector{UInt8}, name::String)::String
    match(name * r":[\s\S]+?\r\n(?=([^ \t]|$))", String(copy(header)), 1).match
end

function get_date_line(header::Vector{UInt8})::String
    get_header_line(header, "Date")
end

function get_message_id_line(header::Vector{UInt8})::String
    get_header_line(header, "Message-ID")
end

@testset "SendEML" begin
    @testset "make_simple_mail_text" begin
        text = make_simple_mail_text()
        lines = split(text, "\r\n")
        @test length(lines) == 13
        @test lines[1] == "From: a001 <a001@ah62.example.jp>"
        @test lines[13] == "test"
    end

    @testset "make_simple_mail" begin
        mail = make_simple_mail()
        @test typeof(mail) == Vector{UInt8}
    end

    @testset "get_header_line" begin
        mail = make_simple_mail()
        @test "Date: Sun, 26 Jul 2020 22:01:37 +0900\r\n" == get_date_line(mail)
        @test "Message-ID: <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>\r\n" == get_message_id_line(mail)

        f_mail = make_folded_mail()
        @test "Date:\r\n Sun, 26 Jul 2020\r\n 22:01:37 +0900\r\n" == get_date_line(f_mail)
        @test "Message-ID:\r\n <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>\r\n" == get_message_id_line(f_mail)

        e_date = make_folded_end_date()
        @test "Date:\r\n Sun, 26 Jul 2020\r\n 22:01:37 +0900\r\n" == get_date_line(e_date)

        e_message_id = make_folded_end_message_id()
        @test "Message-ID:\r\n <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>\r\n" == get_message_id_line(e_message_id)
    end

     @testset "match_header" begin
        function match(s1::String, s2::String)::Bool
            SendEML.match_header(Vector{UInt8}(s1), Vector{UInt8}(s2))
        end

        @test match("Test:", "Test:") == true
        @test match("Test: ", "Test:") == true
        @test match("Test: xxx", "Test:") == true

        @test match("", "Test:") == false
        @test match("T", "Test:") == false
        @test match("Test", "Test:") == false

        @test_throws ErrorException match("Test: xxx", "")
    end

    @testset "find_cr_index" begin
        mail = make_simple_mail()
        @test SendEML.find_cr_index(mail, 1) == 34
        @test SendEML.find_cr_index(mail, 35) == 49
        @test SendEML.find_cr_index(mail, 59) == 75
    end

    @testset "find_lf_index" begin
        mail = make_simple_mail()
        @test SendEML.find_lf_index(mail, 1) == 35
        @test SendEML.find_lf_index(mail, 36) == 50
        @test SendEML.find_lf_index(mail, 60) == 76
    end

    @testset "find_all_lf_indices" begin
        mail = make_simple_mail()
        indices = SendEML.find_all_lf_indices(mail)

        @test indices[1] == 35
        @test indices[2] == 50
        @test indices[3] == 76

        @test indices[end-2] == 391
        @test indices[end-1] == 416
        @test indices[end] == 418
    end

    @testset "get_raw_lines" begin
        mail = make_simple_mail()
        lines = SendEML.get_raw_lines(mail)

        @test length(lines) == 13

        @test lines[1] == b"From: a001 <a001@ah62.example.jp>\r\n"
        @test lines[2] == b"Subject: test\r\n"
        @test lines[3] == b"To: a002@ah62.example.jp\r\n"

        @test lines[end-2] == b"Content-Language: en-US\r\n"
        @test lines[end-1] == b"\r\n"
        @test lines[end] == b"test"
    end

    @testset "is_not_update" begin
        @test SendEML.is_not_update(true, true) == false
        @test SendEML.is_not_update(true, false) == false
        @test SendEML.is_not_update(false, true) == false
        @test SendEML.is_not_update(false, false) == true
    end 

    @testset "make_now_date_line" begin
        line = SendEML.make_now_date_line()
        @test startswith(line, "Date: ")
        @test endswith(line, SendEML.CRLF)
        @test length(line) <= 80
    end

    @testset "make_random_message_id_line" begin
        line = SendEML.make_random_message_id_line()
        @test startswith(line, "Message-ID: ")
        @test endswith(line, SendEML.CRLF)
        @test length(line) <= 80
    end

    @testset "is_wsp" begin
        @test SendEML.is_wsp(UInt8(' ')) == true
        @test SendEML.is_wsp(UInt8('\t')) == true
        @test SendEML.is_wsp(UInt8('\0')) == false
        @test SendEML.is_wsp(UInt8('a')) == false
        @test SendEML.is_wsp(UInt8('b')) == false
    end

    @testset "first_byte" begin
        @test SendEML.first_byte(SendEML.DATE_BYTES, UInt8('0')) == UInt8('D')
        @test SendEML.first_byte(SendEML.MESSAGE_ID_BYTES, UInt8('0')) == UInt8('M')
        @test SendEML.first_byte(Vector{UInt8}(), UInt8('0')) == UInt8('0')
    end

    @testset "first_char" begin
        @test SendEML.first_char("Date:", '0') == 'D'
        @test SendEML.first_char("Message-ID:", '0') == 'M'
        @test SendEML.first_char("", '0') == '0'
    end

    @testset "is_folded_line" begin
        function match(chars::Vararg{Char})::Bool
            array = collect(Iterators.flatten(chars))
            SendEML.is_folded_line(map(UInt8, array))
        end

        @test match(' ', 'a', 'b') == true
        @test match('\t', 'a', 'b') == true
        @test match('\0', 'a', 'b') == false
        @test match('a', 'a', ' ') == false
        @test match('b', 'a', '\t') == false
    end

    @testset "replace_date_line" begin
        f_mail = make_folded_mail()
        lines = SendEML.get_raw_lines(f_mail)
        new_lines = SendEML.replace_date_line(lines)
        @test lines != new_lines

        new_mail = SendEML.concat_bytes(new_lines)
        @test f_mail != new_mail
        @test get_date_line(f_mail) != get_date_line(new_mail)
        @test get_message_id_line(f_mail) == get_message_id_line(new_mail)
    end

    @testset "replace_message_id_line" begin
        f_mail = make_folded_mail()
        lines = SendEML.get_raw_lines(f_mail)
        new_lines = SendEML.replace_message_id_line(lines)
        @test lines != new_lines

        new_mail = SendEML.concat_bytes(new_lines)
        @test f_mail != new_mail
        @test get_message_id_line(f_mail) != get_message_id_line(new_mail)
        @test get_date_line(f_mail) == get_date_line(new_mail)
    end

    @testset "replace_header" begin
        mail = make_simple_mail()
        date_line = get_date_line(mail)
        mid_line = get_message_id_line(mail)

        repl_header_noupdate = SendEML.replace_header(mail, false, false)
        @test mail == repl_header_noupdate

        repl_header = SendEML.replace_header(mail, true, true)
        @test mail != repl_header

        function replace_header(header::Vector{UInt8}, update_date::Bool, update_message_id::Bool)::Tuple{String, String}
            r_header = SendEML.replace_header(header, update_date, update_message_id)
            @test header != r_header
            (get_date_line(r_header), get_message_id_line(r_header))
        end

        (r_date_line, r_mid_line) = replace_header(mail, true, true)
        @test date_line != r_date_line
        @test mid_line != r_mid_line

        (r_date_line, r_mid_line) = replace_header(mail, true, false)
        @test date_line != r_date_line
        @test mid_line == r_mid_line

        (r_date_line, r_mid_line) = replace_header(mail, false, true)
        @test date_line == r_date_line
        @test mid_line != r_mid_line

        f_mail = make_folded_mail()
        (f_date_line, f_mid_line) = replace_header(f_mail, true, true)
        @test count(c -> (c == '\n'), f_date_line) == 1
        @test count(c -> (c == '\n'), f_mid_line) == 1
    end

    @testset "concat_bytes" begin
        mail = make_simple_mail()
        lines = SendEML.get_raw_lines(mail)
        new_mail = SendEML.concat_bytes(lines)
        @test mail == new_mail
    end

    @testset "combine_mail" begin
        mail = make_simple_mail()
        (header, body) = SendEML.split_mail(mail)
        new_mail = SendEML.combine_mail(header, body)
        @test mail == new_mail
    end

    @testset "find_empty_line" begin
        mail = make_simple_mail()
        @test SendEML.find_empty_line(mail) == 415

        invalid_mail = make_invalid_mail()
        @test SendEML.find_empty_line(invalid_mail) === nothing
    end

    @testset "split_mail" begin
        mail = make_simple_mail()
        header_body = SendEML.split_mail(mail)
        @test header_body !== nothing

        (header, body) = header_body
        @test mail[1:414] == header
        @test mail[(415 + 4):end] == body

        invalid_mail = make_invalid_mail()
        @test SendEML.split_mail(invalid_mail) === nothing
    end

    @testset "replace_mail" begin
        mail = make_simple_mail()
        repl_mail_noupdate = SendEML.replace_mail(mail, false, false)
        @test mail == repl_mail_noupdate

        repl_mail = SendEML.replace_mail(mail, true, true)
        @test mail != repl_mail
        @test mail[end-100:end] == repl_mail[end-100:end]

        invalid_mail = make_invalid_mail()
        @test isnothing(SendEML.replace_mail(invalid_mail, true, true))
    end

    @testset "get_and_map_settings" begin
        text = SendEML.make_json_sample()
        settings = SendEML.map_settings(SendEML.get_settings_from_text(text))

        @test settings.smtp_host == "172.16.3.151"
        @test settings.smtp_port == 25
        @test settings.from_address == "a001@ah62.example.jp"
        @test settings.to_addresses == ["a001@ah62.example.jp", "a002@ah62.example.jp", "a003@ah62.example.jp"]
        @test settings.eml_files == ["test1.eml", "test2.eml", "test3.eml"]
        @test settings.update_date == true
        @test settings.update_message_id == true
        @test settings.use_parallel == false
    end

    @testset "is_last_reply" begin
        @test SendEML.is_last_reply("250-First line") == false
        @test SendEML.is_last_reply("250-Second line") == false
        @test SendEML.is_last_reply("250-234 Text beginning with numbers") == false
        @test SendEML.is_last_reply("250 The last line") == true
    end

    @testset "is_positive_reply" begin
        @test SendEML.is_positive_reply("200 xxx") == true
        @test SendEML.is_positive_reply("300 xxx") == true
        @test SendEML.is_positive_reply("400 xxx") == false
        @test SendEML.is_positive_reply("500 xxx") == false
        @test SendEML.is_positive_reply("xxx 200") == false
        @test SendEML.is_positive_reply("xxx 300") == false
    end

    @testset "replace_crlf_dot" begin
        @test SendEML.replace_crlf_dot("TEST") == "TEST"
        @test SendEML.replace_crlf_dot("CRLF") == "CRLF"
        @test SendEML.replace_crlf_dot(SendEML.CRLF) == SendEML.CRLF
        @test SendEML.replace_crlf_dot(".") == "."
        @test SendEML.replace_crlf_dot("$(SendEML.CRLF).") == "<CRLF>."
    end

    @testset "send_hello" begin
        SendEML.send_hello(make_test_send_cmd("EHLO localhost"))
    end

    @testset "send_from" begin
        SendEML.send_from(make_test_send_cmd("MAIL FROM: <a001@ah62.example.jp>"), "a001@ah62.example.jp")
    end

    @testset "send_rcpt_to" begin
        count = 1
        test_func = cmd -> begin
            @test "RCPT TO: <a00$(count)@ah62.example.jp>" == cmd
            count += 1
            cmd
        end

        SendEML.send_rcpt_to(test_func, ["a001@ah62.example.jp", "a002@ah62.example.jp", "a003@ah62.example.jp"])
    end

    @testset "send_data" begin
        SendEML.send_data(make_test_send_cmd("DATA"))
    end

    @testset "send_crlf_dot" begin
        SendEML.send_crlf_dot(make_test_send_cmd("$(SendEML.CRLF)."))
    end

    @testset "send_quit" begin
        SendEML.send_quit(make_test_send_cmd("QUIT"))
    end

    @testset "send_rset" begin
        SendEML.send_rset(make_test_send_cmd("RSET"))
    end

    @testset "check_settings" begin
        function check_no_key(key::String)
            json = SendEML.make_json_sample()
            no_key = replace(json, key => "X-$key")
            SendEML.check_settings(SendEML.get_settings_from_text(no_key))
        end

        @test_throws ErrorException check_no_key("smtpHost")
        @test_throws ErrorException check_no_key("smtpPort")
        @test_throws ErrorException check_no_key("fromAddress")
        @test_throws ErrorException check_no_key("toAddresses")
        @test_throws ErrorException check_no_key("emlFiles")

        @test_nowarn check_no_key("updateDate")
        @test_nowarn check_no_key("updateMessageId")
        @test_nowarn check_no_key("useParallel")
    end

    @testset "proc_json_file" begin
        @test_throws ErrorException SendEML.proc_json_file("__test__")
    end

    import JSON

    @testset "check_json_value" begin
        function check(json::String, type::Type)
            SendEML.check_json_value(JSON.parse(json), "test", type)
        end

        function check_error(json::String, type::Type, expected::String)
            try
                check(json, type)
                @test false
            catch e
                @test isa(e, ErrorException)
                @test e.msg == expected
            end
        end

        json = """{"test": "172.16.3.151"}"""
        @test_nowarn check(json, String)
        @test_throws ErrorException check(json, Int)
        check_error(json, Bool, "test: Invalid type: 172.16.3.151")

        json = """{"test": 172}"""
        @test_nowarn check(json, Int)
        @test_throws ErrorException check(json, String)
        check_error(json, Bool, "test: Invalid type: 172")

        json = """{"test": true}"""
        @test_nowarn check(json, Bool)
        @test_nowarn check(json, Int) # true <=> 1
        check_error(json, String, "test: Invalid type: true")

        json = """{"test": false}"""
        @test_nowarn check(json, Bool)
        @test_nowarn check(json, Int) # false <=> 0
        check_error(json, String, "test: Invalid type: false")

        json = """{"test": ["172.16.3.151", "172.16.3.152", "172.16.3.153"]}"""
        @test_nowarn check(json, Vector{String})
        check_error(json, String, "test: Invalid type: Any[\"172.16.3.151\", \"172.16.3.152\", \"172.16.3.153\"]")

        json = """{"test": ["172.16.3.151", "172.16.3.152", 172]}"""
        check_error(json, Vector{String}, "test: Invalid type: Any[\"172.16.3.151\", \"172.16.3.152\", 172]")
    end
end