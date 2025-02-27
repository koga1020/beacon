defmodule Beacon.PagesTest do
  use Beacon.DataCase

  import Beacon.Fixtures
  alias Beacon.Pages
  alias Beacon.Pages.Page

  defp create_page(_) do
    page_fixture()
    :ok
  end

  describe "list_pages/1" do
    setup [:create_page]

    test "list pages" do
      assert [%Page{}] = Pages.list_pages()
    end
  end

  test "list_pages_for_site order" do
    page_fixture(path: "blog_a", order: 0)
    page_fixture(path: "blog/posts", order: 0)
    page_fixture(path: "blog_b", order: 1)

    assert [%{path: "blog_a"}, %{path: "blog/posts"}, %{path: "blog_b"}] = Pages.list_pages_for_site(:my_site, [:events, :helpers])
  end
end
