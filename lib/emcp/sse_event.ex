defmodule EMCP.SSEEvent do
  @moduledoc "Encodes Server-Sent Events in wire format."

  def encode(data, id) do
    "id: #{id}\nevent: message\ndata: #{data}\n\n"
  end

  def keepalive do
    ": keepalive\n\n"
  end
end
