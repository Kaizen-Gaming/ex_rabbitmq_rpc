import Config

config :logger, :level, :error

config :exrabbitmq, :accounting_enabled, true

config :exrabbitmq, :message_buffering_enabled, true

config :exrabbitmq, :logging_enabled, true

config :exrabbitmq, :test_connection,
  username: "guest",
  password: "guest",
  host: "localhost",
  pool: [size: 1, max_overflow: 0]

config :exrabbitmq, :test_session,
  queue: "ex_rabbitmq_rpc_test",
  consume_opts: [no_ack: false],
  declarations: [
    {:queue,
     [
       name: "ex_rabbitmq_rpc_test",
       opts: [auto_delete: true]
     ]}
  ]
