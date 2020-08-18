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
    const SPACE = UInt8(' ')
    const HTAB = UInt8('\t')
    const CRLF = "\r\n"

    const DATE_BYTES = Vector{UInt8}("Date:")
    const MESSAGE_ID_BYTES = Vector{UInt8}("Message-ID:")

    function find_cr_index(file_buf::Vector{UInt8}, offset::Int)::Union{Int, Nothing}
        findnext(b -> b == CR, file_buf, offset)
    end

    function find_lf_index(file_buf::Vector{UInt8}, offset::Int)::Union{Int, Nothing}
        findnext(b -> b == LF, file_buf, offset)
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
        if length(line) < length(header)
            return false
        end

        for i = eachindex(header)
            if header[i] != line[i]
                return false
            end
        end

        true
    end

    function is_date_line(line::Vector{UInt8})::Bool
        match_header_field(line, DATE_BYTES)
    end

    function is_message_id_line(line::Vector{UInt8})::Bool
        match_header_field(line, MESSAGE_ID_BYTES)
    end

    function make_now_date_line()::String
        time = TimeZones.now(TimeZones.localzone())
        offset = replace(Dates.format(time, "zzzz"), ":" => "", count = 1)
        date_str = Dates.format(time, "eee, dd uuu yyyy HH:MM:SS ")
        "Date: " * date_str * offset * CRLF
    end

    function make_random_message_id_line()::String
        length = 62
        rand_str = Random.randstring(length)
        "Message-ID: <$rand_str>$CRLF"
    end

    function concat_bytes(lines::Vector{Vector{UInt8}})::Vector{UInt8}
        buf = Vector{UInt8}(undef, sum(l -> length(l), lines))
        offset = 1
        for l in lines
            copyto!(buf, offset, l)
            offset += length(l)
        end
        buf
    end

    function is_not_update(update_date::Bool, update_message_id::Bool)::Bool
        !update_date && !update_message_id
    end

    function is_wsp(b::UInt8)::Bool
        b == SPACE || b == HTAB
    end

    function Base.first(array::AbstractArray{T}, default::T)::T where T
        it = iterate(array)
        isnothing(it) ? default : it[1]
    end

    function is_folded_line(bytes::Vector{UInt8})::Bool
        is_wsp(first(bytes, UInt8(0)))
    end

    function replace_header(header::Vector{UInt8}, update_date::Bool, update_messge_id::Bool)::Vector{UInt8}
        if is_not_update(update_date, update_messge_id)
            return header
        end

        lines = get_raw_lines(header)

        function remove_folding(idx::Int)
            i = idx
            while i < length(lines)
                if is_folded_line(lines[i])
                    lines[i] = Vector{UInt8}()
                    i += 1
                else
                    break
                end
            end
        end

        if update_date
            idx = findnext(is_date_line, lines, 1)
            if !isnothing(idx)
                lines[idx] = Vector{UInt8}(make_now_date_line())
                remove_folding(idx + 1)
            end
        end

        if update_messge_id
            idx = findnext(is_message_id_line, lines, 1)
            if !isnothing(idx)
                lines[idx] = Vector{UInt8}(make_random_message_id_line())
                remove_folding(idx + 1)
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

        concat_bytes(lines)
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

    function replace_mail(file_buf::Vector{UInt8}, update_date::Bool, update_message_id::Bool)::Vector{UInt8}
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
        !isnothing(match(LAST_REPLY_REGEX, line))
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

    function make_id_prefix(use_parallel::Bool)::String
        use_parallel ? "id: $(Threads.threadid()), " : ""
    end

    function send_mail(sock::Sockets.TCPSocket, file::String, update_date::Bool, update_message_id::Bool, use_parallel::Bool = false)
        println(make_id_prefix(use_parallel) * "send: $file")

        buf = replace_mail(read(file), update_date, update_message_id)
        write(sock, buf)
        flush(sock)
    end

    function recv_line(sock::Sockets.TCPSocket, use_parallel::Bool = false)::String
        while true
            line = readline(sock)
            if isempty(line)
                error("Connection closed by foreign host")
            end

            println(make_id_prefix(use_parallel) * "recv: $line")

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

    function send_line(sock::Sockets.TCPSocket, cmd::String, use_parallel::Bool = false)
        println(make_id_prefix(use_parallel) * "send: $(replace_crlf_dot(cmd))")

        write(sock, cmd * CRLF)
        flush(sock)
    end

    function make_send_cmd(sock::Sockets.TCPSocket, use_parallel::Bool)::Function
        cmd -> begin
            send_line(sock, cmd, use_parallel)
            recv_line(sock, use_parallel)
        end
    end

    function send_hello(send::Function)::String
        send("EHLO localhost")
    end

    function send_from(send::Function, from_addr::String)::String
        send("MAIL FROM: <$from_addr>")
    end
    
    function send_rcpt_to(send::Function, to_addrs::Vector{String})
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

    struct Settings
        smtp_host::String
        smtp_port::Int
        from_address::String
        to_address::Vector{String}
        eml_file::Vector{String}
        update_date::Bool
        update_message_id::Bool
        use_parallel::Bool
    end

    function send_messages(settings::Settings, eml_files::Vector{String}, use_parallel::Bool)
        sock = Sockets.connect(settings.smtp_host, settings.smtp_port)
        send = make_send_cmd(sock, use_parallel)
        recv_line(sock, use_parallel)
        send_hello(send)

        try
            reset = false
            for file in eml_files
                if !isfile(file)
                    println("$file: EML file does not exist")
                    continue
                end

                if reset
                    println("---")
                    send_rset(send)
                end

                send_from(send, settings.from_address)
                send_rcpt_to(send, settings.to_address)
                send_data(send)

                try
                    send_mail(sock, file, settings.update_date, settings.update_message_id, use_parallel)
                catch e
                    msg = isa(e, ErrorException) ? e.msg : e
                    error("$file: $msg")
                end

                send_crlf_dot(send)
                reset = true
            end
            send_quit(send)
        finally
            close(sock)
        end
    end

    function check_json_value(json::Dict{String, Any}, name::String, type::Type)
        if haskey(json, name)
            try
                convert(type, json[name])
            catch e
                error("$name: Invalid type: $(json[name])")
            end
        end
    end

    function check_settings(json::Dict{String, Any})
        names = ["smtpHost", "smtpPort", "fromAddress", "toAddress", "emlFile"];
        key_idx = findfirst(n -> !haskey(json, n), names);
        if !isnothing(key_idx)
            error("$(names[key_idx]) key does not exist")
        end

        check_json_value(json, "smtpHost", String)
        check_json_value(json, "smtpPort", Int)
        check_json_value(json, "fromAddress", String)
        check_json_value(json, "toAddress", Vector{String})
        check_json_value(json, "emlFile", Vector{String})
        check_json_value(json, "updateDate", Bool)
        check_json_value(json, "updateMessageId", Bool)
        check_json_value(json, "useParallel", Bool)
    end

    function get_settings_from_text(text::String)::Dict{String, Any}
        JSON.parse(text)
    end

    function get_settings(json_file::String)::Dict{String, Any}
        get_settings_from_text(read(json_file, String))
    end

    function map_settings(settings::Dict{String, Any})::Settings
        Settings(
            settings["smtpHost"],
            settings["smtpPort"],
            settings["fromAddress"],
            settings["toAddress"],
            settings["emlFile"],
            get(settings, "updateDate", true),
            get(settings, "updateMessageId", true),
            get(settings, "useParallel", false)
        )
    end

    function proc_json_file(json_file::String)
        if !isfile(json_file)
            error("JSON file does not exist")
        end

        # ! Avoid JSON.parsefile(): file not closed
        json = get_settings(json_file)
        check_settings(json)
        settings = map_settings(json)

        if settings.use_parallel && length(settings.eml_file) > 1
            if Threads.nthreads() == 1
                println("Threads.nthreads() == 1")
                println("    Windows: `set JULIA_NUM_THREADS=4` or `\$env:JULIA_NUM_THREADS=4`(PowerShell)")
                println("    Other: `export JULIA_NUM_THREADS=4`")
                println("---")
            end

            Threads.@threads for f in settings.eml_file
                send_messages(settings, Vector{String}([f]), true)
            end
        else
            send_messages(settings, settings.eml_file, false)
        end
    end

    function main()
        if isempty(ARGS)
            print_usage()
            exit(0)
        end

        if ARGS[1] == "--version"
            print_version()
            exit(0)
        end

        for json_file in ARGS
            try
                proc_json_file(json_file)
            catch e
                msg = isa(e, ErrorException) ? e.msg : e
                println("error: $json_file: $msg")
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