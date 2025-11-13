defmodule Backpex.NotAnAuthCheck do
  @moduledoc """
  An `Ash.Resource.Validation` that can be used to determine whether validations are currently being run as part of an
  authorization check.

  This is useful to skip computationally expensive validations if they are not needed for authorization checks. See
  [Backpex.Adapters.Ash](Backpex.Adapters.Ash.html#module-validations) for an example of how to use this feature.
  """

  use Ash.Resource.Validation

  @impl true
  def supports(_opts), do: [Ash.Changeset]

  @impl true
  def validate(_changeset, _opts, context) do
    if context.source_context[:backpex_authorization_check] do
      {:error, message: "This is a Backpex authorization check"}
    else
      :ok
    end
  end
end
