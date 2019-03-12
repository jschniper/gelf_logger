# GelfLogger [![Build Status](https://travis-ci.org/jschniper/gelf_logger.svg?branch=master)](https://travis-ci.org/jschniper/gelf_logger)

A logger backend that will generate Graylog Extended Log Format messages. The
current version only supports UDP messages.

## Configuration

In the config.exs, add gelf_logger as a backend like this:

```
config :logger,
  backends: [:console, {Logger.Backends.Gelf, :gelf_logger}]
```

In addition, you'll need to pass in some configuration items to the backend
itself:

```
config :logger, :gelf_logger,
  host: "127.0.0.1",
  port: 12201,
  format: "$message",
  application: "myapp",
  compression: :gzip, # Defaults to :gzip, also accepts :zlib or :raw
  metadata: [:request_id, :function, :module, :file, :line],
  hostname: "hostname-override",
  tags: [
    list: "of",
    extra: "tags"
  ]
```

In addition to the backend configuration, you might want to check the 
[Logger configuration](https://hexdocs.pm/logger/Logger.html) for other 
options that might be important for your particular environment. In 
particular, modifying the `:utc_log` setting might be necessary 
depending on your server configuration.
This backend supports `metadata: :all`.

## Usage

Just use Logger as normal.

## Improvements

- [x] Tests
- [ ] TCP Support
- [x] Options for compression (none, zlib)
- [x] Send timestamp instead of relying on the Graylog server to set it
- [x] Find a better way of pulling the hostname

And probably many more. This is only out here because it might be useful to
someone in its current state. Pull requests are always welcome.

## Notes

Credit where credit is due, this would not exist without
[protofy/erl_graylog_sender](https://github.com/protofy/erl_graylog_sender).

