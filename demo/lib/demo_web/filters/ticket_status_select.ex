defmodule DemoWeb.Filters.TicketStatusSelect do
  @moduledoc """
  Implementation of the `Backpex.Filters.Select` behaviour.
  """

  use Backpex.Filters.Select

  alias Demo.Category
  alias Demo.Post
  alias Demo.Repo

  @impl Backpex.Filter
  def label, do: "Status"

  @impl Backpex.Filters.Select
  def prompt, do: "Select status ..."

  @impl Backpex.Filters.Select
  def options(_assigns) do
    Map.new(Demo.Helpdesk.Ticket.status_options(), &{Atom.to_string(&1), &1})
  end
end
