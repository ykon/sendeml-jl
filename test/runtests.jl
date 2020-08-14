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
        @test "Date: Sun, 26 Jul 2020 22:01:37 +0900\r\n" == get_header_line(mail, "Date")
        @test "Message-ID: <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>\r\n" == get_header_line(mail, "Message-ID")

        folded_mail = make_folded_mail()
        @test "Date:\r\n Sun, 26 Jul 2020\r\n 22:01:37 +0900\r\n" == get_header_line(folded_mail, "Date")
        @test "Message-ID:\r\n <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>\r\n" == get_header_line(folded_mail, "Message-ID")

        end_date = make_folded_end_date()
        @test "Date:\r\n Sun, 26 Jul 2020\r\n 22:01:37 +0900\r\n" == get_header_line(end_date, "Date")

        end_message_id = make_folded_end_message_id()
        @test "Message-ID:\r\n <b0e564a5-4f70-761a-e103-70119d1bcb32@ah62.example.jp>\r\n" == get_header_line(end_message_id, "Message-ID")
    end

    @testset "match_header_field" begin
        match = (s1, s2) -> SendEML.match_header_field(Vector{UInt8}(s1), Vector{UInt8}(s2))

        @test match("Test:", "Test:") == true
        @test match("Test: ", "Test:") == true
        @test match("Test:x", "Test:") == true

        @test match("", "Test:") == false
        @test match("T", "Test:") == false
        @test match("Test", "Test:") == false
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

    @testset "is_first_wsp" begin
        @test SendEML.is_first_wsp(Vector{UInt8}([UInt8(' '), UInt8('a'), UInt8('b')])) == true
        @test SendEML.is_first_wsp(Vector{UInt8}([UInt8('\t'), UInt8('a'), UInt8('b')])) == true
        @test SendEML.is_first_wsp(Vector{UInt8}([UInt8('\0'), UInt8('a'), UInt8('b')])) == false
        @test SendEML.is_first_wsp(Vector{UInt8}([UInt8('a'), UInt8('b'), UInt8(' ')])) == false
        @test SendEML.is_first_wsp(Vector{UInt8}([UInt8('a'), UInt8('b'), UInt8('\t')])) == false
    end

    @testset "replace_header" begin
        (header, _) = SendEML.split_mail(make_simple_mail())
        date_line = get_date_line(header)
        mid_line = get_message_id_line(header)

        repl_header_noupdate = SendEML.replace_header(header, false, false)
        @test header == repl_header_noupdate

        repl_header = SendEML.replace_header(header, true, true)
        @test header != repl_header

        function replace_header(header::Vector{UInt8}, update_date::Bool, update_message_id::Bool)::Tuple{String, String}
            r_header = SendEML.replace_header(header, update_date, update_message_id)
            @test header != r_header
            (get_date_line(r_header), get_message_id_line(r_header))
        end

        (r_date_line, r_mid_line) = replace_header(header, true, true)
        @test date_line != r_date_line
        @test mid_line != r_mid_line

        (r_date_line, r_mid_line) = replace_header(header, true, false)
        @test date_line != r_date_line
        @test mid_line == r_mid_line

        (r_date_line, r_mid_line) = replace_header(header, false, true)
        @test date_line == r_date_line
        @test mid_line != r_mid_line

        (folded_header, _) = SendEML.split_mail(make_folded_mail())
        (f_date_line, f_mid_line) = replace_header(folded_header, true, true)
        @test count(c -> (c == '\n'), f_date_line) == 1
        @test count(c -> (c == '\n'), f_mid_line) == 1
    end

    @testset "concat_raw_lines" begin
        mail = make_simple_mail()
        lines = SendEML.get_raw_lines(mail)
        new_mail = SendEML.concat_raw_lines(lines)
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

    @testset "replace_raw_bytes" begin
        mail = make_simple_mail()
        repl_mail_noupdate = SendEML.replace_raw_bytes(mail, false, false)
        @test mail == repl_mail_noupdate

        repl_mail = SendEML.replace_raw_bytes(mail, true, true)
        @test mail != repl_mail
        @test mail[end-100:end] == repl_mail[end-100:end]

        invalid_mail = make_invalid_mail()
        @test_throws ErrorException SendEML.replace_raw_bytes(invalid_mail, true, true)
    end

    @testset "get_settings_from_text" begin
        text = SendEML.make_json_sample()
        json = SendEML.get_settings_from_text(text)

        @test json["smtpHost"] == "172.16.3.151"
        @test json["smtpPort"] == 25
        @test json["fromAddress"] == "a001@ah62.example.jp"
        @test json["toAddress"] == ["a001@ah62.example.jp", "a002@ah62.example.jp", "a003@ah62.example.jp"]
        @test json["emlFile"] == ["test1.eml", "test2.eml", "test3.eml"]
        @test json["updateDate"] == true
        @test json["updateMessageId"] == true
        @test json["useParallel"] == false
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

        SendEML.send_rcpt_to(test_func, Vector{Any}(["a001@ah62.example.jp", "a002@ah62.example.jp", "a003@ah62.example.jp"]))
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
        @test_throws ErrorException check_no_key("toAddress")
        @test_throws ErrorException check_no_key("emlFile")

        try
            check_no_key("testKey")
        catch e
            @test false
        end
    end

    @testset "proc_json_file" begin
        @test_throws ErrorException SendEML.proc_json_file("__test__")
    end
end