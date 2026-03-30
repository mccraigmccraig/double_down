defmodule HexPort do
  @moduledoc """
  Hexagonal architecture ports for Elixir.

  HexPort provides typed port contracts with async-safe test doubles,
  dispatch logging, and stateful test handlers. Define boundaries with
  `defport`, swap implementations for testing without a database.

  ## Defining a Contract

      defmodule MyApp.Todos do
        use HexPort.Contract

        defport get_todo(tenant_id :: String.t(), id :: String.t()) ::
          {:ok, Todo.t()} | {:error, term()}

        defport list_todos(tenant_id :: String.t()) :: [Todo.t()]
      end

  This generates:

    * `MyApp.Todos.Behaviour` — standard `@behaviour` with `@callback`s
    * `MyApp.Todos.__port_operations__/0` — operation metadata

  ## Generating a Dispatch Facade

      defmodule MyApp.Todos.Port do
        use HexPort.Port, contract: MyApp.Todos, otp_app: :my_app
      end

  This generates facade functions, bang variants, and key helpers
  that dispatch via `HexPort.Dispatch`.

  ## Configuration

      # config/config.exs
      config :my_app, MyApp.Todos, impl: MyApp.Todos.Ecto

  ## Testing

      # test/test_helper.exs
      HexPort.Testing.start()

      # test/my_test.exs
      setup do
        HexPort.Testing.set_fn_handler(MyApp.Todos, fn
          :get_todo, [_tenant, id] -> {:ok, %Todo{id: id}}
          :list_todos, [_tenant] -> []
        end)
        :ok
      end

      test "gets a todo" do
        assert {:ok, %Todo{}} = MyApp.Todos.Port.get_todo("t1", "todo-1")
      end
  """
end
