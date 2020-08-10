#=
    Copyright (c) Yuki Ono.
    Licensed under the MIT License.
=#

module SendEML
    import Dates
    import TimeZones
    import Random
    import JSON
    import Sockets

    const VERSION = 1.0

    const CR = UInt8('\r')
    const LF = UInt8('\n')
    const CRLF = "\r\n"

    const DATE_BYTES = Vector{UInt8}("Date: ")
    const MESSAGE_ID_BYTES = Vector{UInt8}("Message-ID: ")

    USE_PARALLEL = false

    function find_cr_index(file_buf::Vector{UInt8}, offset::Int)::Union{Int, Nothing}
        findnext(b -> b === CR, file_buf, offset)
    end

    function find_lf_index(file_buf::Vector{UInt8}, offset::Int)::Union{Int, Nothing}
        findnext(b -> b === LF, file_buf, offset)
    end

    function find_all_lf_indices(file_buf::Vector{UInt8})::Vector{Int}
        indices = Int[]
        offset = 1
        while true
            idx = find_lf_index(file_buf, offset)
            if isnothing(idx)
                return indices
            end

            push!(indices, idx)
            offset = idx + 1
        end
    end

    function get_raw_lines(file_buf::Vector{UInt8})::Vector{Vector{UInt8}}
        indices = find_all_lf_indices(file_buf)
        push!(indices, length(file_buf))
        offset = 1
        map(i -> begin
            line = file_buf[offset:i]
            offset = i + 1
            return line
        end, indices)
    end

    function match_header_field(line::Vector{UInt8}, header::Vector{UInt8})::Bool
        line[1:length(header)] == header
    end

    function is_date_line(line::Vector{UInt8})::Bool
        match_header_field(line, DATE_BYTES)
    end

    function is_message_id_line(line::Vector{UInt8})::Bool
        match_header_field(line, MESSAGE_ID_BYTES)
    end

    function make_now_date_line()::String
        time = TimeZones.now(TimeZones.localzone())
        offset = replace(Dates.format(time, "zzzz"), ":" => "", count=1)
        "Date: " * Dates.format(time, "eee, dd uuu yyyy HH:MM:SS ") * offset * CRLF
    end

    function make_random_message_id_line()::String
        length = 62
        randstr = Random.randstring(length)
        "Message-ID: <$randstr>$CRLF"
    end

    function concat_raw_lines(lines::Vector{Vector{UInt8}})::Vector{UInt8}
        collect(Iterators.flatten(lines))
    end

    function is_not_update(update_date::Bool, update_message_id::Bool)::Bool
        !update_date && !update_message_id
    end

    function replace_header(header::Vector{UInt8}, update_date::Bool, update_messge_id::Bool)::Vector{UInt8}
        if is_not_update(update_date, update_messge_id)
            return header
        end

        repl_lines = get_raw_lines(header)

        if update_date
            idx = findnext(is_date_line, repl_lines, 1)
            if !isnothing(idx)
                repl_lines[idx] = Vector{UInt8}(make_now_date_line())
            end
        end

        if update_messge_id
            idx = findnext(is_message_id_line, repl_lines, 1)
            if !isnothing(idx)
                repl_lines[idx] = Vector{UInt8}(make_random_message_id_line())
            end
        end

        # ! FixMe: ERROR: MethodError: convert(::Type{Union{}}, ::Array{UInt8,1}) is ambiguous.
        #=
        function replace_line(update::Bool, match_line::Function, make_line::Function)::Nothing
            if update
                idx = findnext(match_line, repl_lines, 1)
                if !isnothing(idx)
                    repl_lines[idx] = Vector{UInt8}(make_line())
                end
            end
        end
        replace_line(update_date, is_date_line, make_now_date_line)
        replace_line(update_messge_id, is_message_id_line, make_random_message_id_line)
        =#

        concat_raw_lines(repl_lines)
    end

    const EMPTY_LINE = [CR, LF, CR, LF]

    function combine_mail(header::Vector{UInt8}, body::Vector{UInt8})::Vector{UInt8}
        vcat(header, EMPTY_LINE, body)
    end

    function find_empty_line(file_buf::Vector{UInt8})::Union{UInt, Nothing}
        offset = 1
        while true
            idx = find_cr_index(file_buf, offset)
            if isnothing(idx) || (idx + 3) >= length(file_buf)
                return nothing
            end

            if file_buf[idx + 1] == LF && file_buf[idx + 2] == CR && file_buf[idx + 3] == LF
                return idx
            end

            offset = idx + 1
        end
    end

    function split_mail(file_buf::Vector{UInt8})::Union{Tuple{Vector{UInt8}, Vector{UInt8}}, Nothing}
        idx = find_empty_line(file_buf)
        if isnothing(idx)
            return nothing
        end

        header = file_buf[1:(idx - 1)]
        body = file_buf[(idx + length(EMPTY_LINE)):end]
        return (header, body)
    end

    function replace_raw_bytes(file_buf::Vector{UInt8}, update_date::Bool, update_message_id::Bool)::Vector{UInt8}
        if is_not_update(update_date, update_message_id)
            return file_buf
        end

        mail = split_mail(file_buf)
        if isnothing(mail)
            error("Invalid mail")
        end

        (header, body) = mail
        repl_header = replace_header(header, update_date, update_message_id)
        combine_mail(repl_header, body)
    end

    function make_json_sample()
        """{
            "smtpHost": "172.16.3.151",
            "smtpPort": 25,
            "fromAddress": "a001@ah62.example.jp",
            "toAddress": [
                "a001@ah62.example.jp",
                "a002@ah62.example.jp",
                "a003@ah62.example.jp"
            ],
            "emlFile": [
                "test1.eml",
                "test2.eml",
                "test3.eml"
            ],
            "updateDate": true,
            "updateMessageId": true,
            "useParallel": false
        }"""
    end

    function print_usage()
        println("Usage: {self} json_file ...")
        println("---")

        println("json_file sample:")
        println(make_json_sample());
    end

    function print_version()
        println("SendEML / Version: $VERSION")
    end

    const LAST_REPLY_REGEX = r"^\d{3} .+"

    function is_last_reply(line::String)::Bool
        match(LAST_REPLY_REGEX, line) !== nothing
    end

    function is_positive_reply(line::String)::Bool
        code = first(line, 1)
        if code == "2"
            true
        elseif code == "3"
            true
        else
            false
        end
    end

    function get_current_id_prefix()::String
        global USE_PARALLEL
        USE_PARALLEL ? "id: $(Threads.threadid()), " : ""
    end

    function send_raw_bytes(sock::Sockets.TCPSocket, file::String, update_date::Bool, update_message_id::Bool)
        println(get_current_id_prefix() * "send: $file")

        buf = replace_raw_bytes(read(file), update_date, update_message_id)
        write(sock, buf)
        flush(sock)
    end

    function recv_line(sock::Sockets.TCPSocket)::String
        while true
            line = readline(sock)
            if isempty(line)
                error("Connection closed by foreign host")
            end

            println(get_current_id_prefix() * "recv: $line")

            if is_last_reply(line)
                if is_positive_reply(line)
                    return line
                end

                error(line)
            end
        end
    end

    function replace_crlf_dot(cmd::String)::String
        cmd == "$CRLF." ? "<CRLF>." : cmd
    end

    function send_line(sock::Sockets.TCPSocket, cmd::String)
        println(get_current_id_prefix() * "send: $(replace_crlf_dot(cmd))")

        write(sock, cmd * CRLF)
        flush(sock)
    end

    function make_send_cmd(sock::Sockets.TCPSocket)::Function
        cmd -> begin
            send_line(sock, cmd)
            recv_line(sock)
        end
    end

    function send_hello(send::Function)::String
        send("EHLO localhost")
    end

    function send_from(send::Function, from_addr::String)::String
        send("MAIL FROM: <$from_addr>")
    end
    
    function send_rcpt_to(send::Function, to_addrs::Vector{Any})
        for addr in to_addrs
            send("RCPT TO: <$addr>")
        end
    end

    function send_data(send::Function)::String
        send("DATA")
    end

    function send_crlf_dot(send::Function)::String
        send("$CRLF.")
    end

    function send_rset(send::Function)::String
        send("RSET")
    end

    function send_quit(send::Function)::String
        send("QUIT")
    end

    function send_messages(settings::Dict{String, Any}, eml_files::Vector{Any})
        sock = Sockets.connect(settings["smtpHost"], settings["smtpPort"])
        send = make_send_cmd(sock)
        recv_line(sock)
        send_hello(send)

        mail_sent = false
        for file in eml_files
            if !isfile(file)
                println("$file: EML file does not exist")
                continue
            end

            if mail_sent
                println("---")
                send_rset(send)
            end

            send_from(send, settings["fromAddress"])
            send_rcpt_to(send, settings["toAddress"])
            send_data(send)
            send_raw_bytes(sock, file, get(settings, "updateDate", true), get(settings, "updateMessageId", true))
            send_crlf_dot(send)
            mail_sent = true
        end
        
        send_quit(send)
    end

    function send_one_message(settings::Dict{String, Any}, file::String)
        send_messages(settings, Vector{Any}([file]))
    end

    function check_settings(settings::Dict{String, Any})
        function not_found_key()::String
            s = settings
            if !haskey(s, "smtpHost")
                "smtpHost"
            elseif !haskey(s, "smtpPort")
                "smtpPort"
            elseif !haskey(s, "fromAddress")
                "fromAddress"
            elseif !haskey(s, "toAddress")
                "toAddress"
            elseif !haskey(s, "emlFile")
                "emlFile"
            else
                ""
            end
        end

        key = not_found_key()
        if !isempty(key)
            error("$key key does not exist")
        end
    end

    function get_settings_from_text(text::String)::Dict{String, Any}
        JSON.parse(text)
    end

    function get_settings(json_file::String)::Dict{String, Any}
        get_settings_from_text(read(json_file, String))
    end

    function proc_json_file(json_file::String)
        if !isfile(json_file)
            error("JSON file does not exist")
        end

        # ! Avoid JSON.parsefile(): file not closed
        settings = get_settings(json_file)
        check_settings(settings)

        if get(settings, "useParallel", false)
            if Threads.nthreads() == 1
                println("Threads.nthreads() == 1")
                println("    Windows: `set JULIA_NUM_THREADS=4` or `\$env:JULIA_NUM_THREADS=4`(PowerShell)")
                println("    Other: `export JULIA_NUM_THREADS=4`")
                println("---")
            end

            global USE_PARALLEL
            USE_PARALLEL = true
            Threads.@threads for f in settings["emlFile"]
                send_one_message(settings, f)
            end
        else
            send_messages(settings, settings["emlFile"])
        end
    end

    function main()
        if isempty(ARGS)
            print_usage()
            exit(0)
        end

        if ARGS[1] === "--version"
            print_version()
            exit(0)
        end

        for json_file in ARGS
            try
                proc_json_file(json_file)
            catch e
                println("$json_file: $(e.msg)")
            end
        end
    end

    Base.@ccallable function julia_main()::Cint
        try
            main()
        catch
            Base.invokelatest(Base.display_error, Base.catch_stack())
            return 1
        end
        return 0
    end

    if abspath(PROGRAM_FILE) == @__FILE__
        main()
    end
end # module