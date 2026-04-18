defmodule DoubleDown.Repo.ExMachinaTest do
  use ExUnit.Case, async: true

  import DoubleDown.Test.Factory

  alias DoubleDown.Test.Factory.User
  alias DoubleDown.Test.Factory.Post

  setup do
    DoubleDown.Double.fake(DoubleDown.Repo, DoubleDown.Repo.InMemory)
    :ok
  end

  # -------------------------------------------------------------------
  # Basic factory usage — insert via ExMachina, read via Repo
  # -------------------------------------------------------------------

  describe "ExMachina insert" do
    test "factory-inserted records are readable via get" do
      user = insert(:user, name: "Alice")

      assert user.id != nil
      assert user.name == "Alice"

      found = DoubleDown.Repo.Port.get(User, user.id)
      assert found.name == "Alice"
    end

    test "factory-inserted records are readable via all" do
      insert(:user, name: "Alice")
      insert(:user, name: "Bob")
      insert(:user, name: "Carol")

      users = DoubleDown.Repo.Port.all(User)
      assert length(users) == 3
      names = Enum.map(users, & &1.name) |> Enum.sort()
      assert names == ["Alice", "Bob", "Carol"]
    end

    test "factory-inserted records are readable via get_by" do
      insert(:user, name: "Alice", email: "alice@example.com")
      insert(:user, name: "Bob", email: "bob@example.com")

      found = DoubleDown.Repo.Port.get_by(User, email: "alice@example.com")
      assert found.name == "Alice"
    end

    test "exists? returns true for factory-inserted records" do
      insert(:user)
      assert DoubleDown.Repo.Port.exists?(User)
    end

    test "exists? returns false when no records" do
      refute DoubleDown.Repo.Port.exists?(User)
    end
  end

  # -------------------------------------------------------------------
  # Aggregates on factory data
  # -------------------------------------------------------------------

  describe "aggregates on factory data" do
    test "count" do
      insert(:user)
      insert(:user)
      insert(:user)

      assert 3 == DoubleDown.Repo.Port.aggregate(User, :count, :id)
    end

    test "avg age" do
      insert(:user, age: 20)
      insert(:user, age: 30)
      insert(:user, age: 40)

      assert 30.0 == DoubleDown.Repo.Port.aggregate(User, :avg, :age)
    end

    test "min/max" do
      insert(:user, age: 18)
      insert(:user, age: 65)

      assert 18 == DoubleDown.Repo.Port.aggregate(User, :min, :age)
      assert 65 == DoubleDown.Repo.Port.aggregate(User, :max, :age)
    end
  end

  # -------------------------------------------------------------------
  # Multiple schema types
  # -------------------------------------------------------------------

  describe "multiple schemas" do
    test "records of different schemas are independent" do
      insert(:user, name: "Alice")
      insert(:post, title: "Hello World")

      assert length(DoubleDown.Repo.Port.all(User)) == 1
      assert length(DoubleDown.Repo.Port.all(Post)) == 1
    end
  end

  # -------------------------------------------------------------------
  # Read-after-write consistency
  # -------------------------------------------------------------------

  describe "read-after-write" do
    test "insert then immediate read" do
      user = insert(:user, name: "Alice")
      assert ^user = DoubleDown.Repo.Port.get(User, user.id)
    end

    test "insert then update then read" do
      user = insert(:user, name: "Alice")

      cs = Ecto.Changeset.cast(user, %{name: "Alicia"}, [:name])
      {:ok, updated} = DoubleDown.Repo.Port.update(cs)

      found = DoubleDown.Repo.Port.get(User, user.id)
      assert found.name == "Alicia"
      assert found.name == updated.name
    end

    test "insert then delete then read" do
      user = insert(:user, name: "Alice")
      {:ok, _} = DoubleDown.Repo.Port.delete(user)

      assert nil == DoubleDown.Repo.Port.get(User, user.id)
      assert [] == DoubleDown.Repo.Port.all(User)
    end
  end

  # -------------------------------------------------------------------
  # Failure simulation with factory data
  # -------------------------------------------------------------------

  describe "failure simulation over factory data" do
    test "layer expects over factory-populated store" do
      insert(:user, name: "Alice")
      insert(:user, name: "Bob")

      # Next insert! will raise — ExMachina calls insert! directly
      DoubleDown.Double.expect(DoubleDown.Repo, :insert!, fn [struct] ->
        cs = Ecto.Changeset.change(struct) |> Ecto.Changeset.add_error(:name, "taken")
        raise Ecto.InvalidChangesetError, action: :insert, changeset: cs
      end)

      assert_raise Ecto.InvalidChangesetError, fn ->
        insert(:user, name: "Carol")
      end

      # Existing records still there
      assert length(DoubleDown.Repo.Port.all(User)) == 2
    end
  end

  # -------------------------------------------------------------------
  # Timestamps
  # -------------------------------------------------------------------

  describe "timestamps" do
    test "factory-inserted records have timestamps" do
      user = insert(:user)
      assert user.inserted_at != nil
      assert user.updated_at != nil
    end
  end
end
