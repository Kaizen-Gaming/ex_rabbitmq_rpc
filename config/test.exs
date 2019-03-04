use Mix.Config

config :logger, level: :error

config :exrabbitmq, :test_connection,
  username: "guest",
  password: "guest",
  host: "localhost"

config :exrabbitmq, :test_session,
  queue: "ex_rabbitmq_rpc_test",
  consume_opts: [no_ack: false],
  declarations: [
    {:queue,
     [
       name: "ex_rabbitmq_rpc_test",
       queue_opts: [auto_delete: true]
     ]}
  ]
