defmodule Beacon.Components.Component do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "beacon_components" do
    field :body, :string
    field :name, :string
    field :site, Beacon.Type.Site

    timestamps()
  end

  @doc false
  def changeset(component, attrs) do
    component
    |> cast(attrs, [:site, :name, :body])
    |> validate_required([:site, :name, :body])
  end
end
