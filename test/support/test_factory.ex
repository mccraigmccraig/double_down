# ExMachina factory for DoubleDown.Repo.InMemory integration tests.
#
# Uses the test DoubleDown.Test.Repo facade module as the repo, so factory inserts
# go through DoubleDown dispatch and land in the InMemory store.

defmodule DoubleDown.Test.Factory do
  use ExMachina.Ecto, repo: DoubleDown.Test.Repo

  defmodule User do
    use Ecto.Schema

    schema "users" do
      field(:name, :string)
      field(:email, :string)
      field(:age, :integer)
      field(:active, :boolean, default: true)
      timestamps()
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
      field(:body, :string)
      field(:author_id, :integer)
      timestamps()
    end
  end

  def user_factory do
    %User{
      name: sequence(:name, &"User #{&1}"),
      email: sequence(:email, &"user#{&1}@example.com"),
      age: 25,
      active: true
    }
  end

  def post_factory do
    %Post{
      title: sequence(:title, &"Post #{&1}"),
      body: "Some content",
      author_id: 1
    }
  end
end
