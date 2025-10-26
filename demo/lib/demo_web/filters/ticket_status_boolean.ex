defmodule DemoWeb.Filters.TicketStatusBoolean do
  @moduledoc """
  Implementation of the `Backpex.Filters.Boolean` behaviour.
  """

  use Backpex.Filters.Boolean

  @impl Backpex.Filter
  def label, do: "Status"

  @impl Backpex.Filters.Boolean
  def options(_assigns) do
    [
      %{
        label: "Open",
        key: "open",
        predicate: [status: :open]
      },
      %{
        label: "Closed",
        key: "closed",
        predicate: [status: :closed]
      }
    ]
  end
end
