use Mix.Config

config :logger,
  level: :error

config :exrabbitmq, :test,
  username: "guest",
  password: "guest",
  host: "localhost",
  queue: "ex_rabbitmq_rpc_test",
  queue_opts: [auto_delete: true],
  consume_opts: [no_ack: false]
