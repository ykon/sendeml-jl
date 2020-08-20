## About
### SendEML is a testing tool for sending raw eml files.
* SendEML-jl runs on Julia 1.5 or newer.
  > [Download Julia](https://julialang.org/downloads/)

## Usage

### Windows
```
julia --project .\src\SendEML.jl <setting_file> ...
```
### Others
```
julia --project ./src/SendEML.jl <setting_file> ...
```

## Setting File (sample)
```
{
    "smtpHost": "172.16.3.151",
    "smtpPort": 25,
    "fromAddress": "a001@ah62.example.jp",
    "toAddresses": [
        "a001@ah62.example.jp",
        "a002@ah62.example.jp",
        "a003@ah62.example.jp"
    ],
    "emlFiles": [
        "test1.eml",
        "test2.eml",
        "test3.eml"
    ],
    "updateDate": true,
    "updateMessageId": true,
    "useParallel": false
}
```

## Options

* updateDate
  - Replace "Date:" line with the current date and time.

* updateMessageId
  - Replace "Message-ID:" line with a new random string ID.

* useParallel
  - Enable parallel processing for eml files.
