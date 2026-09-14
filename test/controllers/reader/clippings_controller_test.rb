require "test_helper"

class Reader::ClippingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    set_reader_credentials!
  end

  teardown do
    restore_reader_credentials!
  end

  test "shows only the clippings waiting for the next issue" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Rails 8\.1 ships with a new queue UI/
    assert_select "body", /Understanding Solid Queue internals/
    assert_select "body", text: /Show HN/, count: 0 # already sent last week
    assert_select "body", /2 recortes aguardando/
  end

  test "shows the summary and its status" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /O Rails 8\.1 traz um novo painel de filas\./
    assert_select "body", /resumo pronto/
    assert_select "body", /resumo pendente/
  end

  test "shows the source feed of each clipping" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Ruby Weekly/
  end

  test "shows both languages of a clipping" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    # The original (en-US) and its pt-BR translation, each labelled.
    assert_select "body", /Rails 8\.1 ships with a new queue UI/
    assert_select "body", /O Rails 8\.1 traz uma nova interface de filas/
    assert_select "body", /original/
    assert_select "body", /tradução/
  end

  test "shows the detected language of a summarized clipping" do
    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /en-US/
    # The one still waiting has no language yet.
    assert_select "body", /idioma não detectado/
  end

  test "flags a translation that is still pending" do
    clipping = clippings(:pending)
    clipping.update_columns(language: "en-US", title_translated: nil, summary_translated: nil,
                            summary_status: "summarized")

    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /tradução pendente/
  end

  test "removing a clipping takes it out of the queue" do
    clipping = clippings(:queued)

    assert_difference -> { Clipping.count }, -1 do
      delete reader_clipping_path(clipping), headers: reader_headers
    end

    assert_redirected_to reader_clippings_path

    get reader_clippings_path, headers: reader_headers
    assert_select ".flash--notice", /Removido da fila/
  end

  test "removing a clipping lets the same entry be clipped again" do
    clipping = clippings(:queued)
    delete reader_clipping_path(clipping), headers: reader_headers

    assert_difference -> { Clipping.count }, 1 do
      post clip_reader_entry_path(clipping.entry), headers: reader_headers
    end
  end

  test "retrying a failed summary requeues it" do
    clipping = clippings(:pending)
    clipping.update!(summary_status: :failed, summary_error: "boom")

    assert_enqueued_with(job: GenerateSummaryJob, args: [ clipping.id ]) do
      post retry_summary_reader_clipping_path(clipping), headers: reader_headers
    end

    clipping.reload
    assert clipping.pending?
    assert_nil clipping.summary_error
    assert_redirected_to reader_clippings_path
  end

  test "an empty queue says so" do
    Clipping.unsent.destroy_all

    get reader_clippings_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Nenhum recorte na fila/
  end

  test "links to the sent issues" do
    get reader_clippings_path, headers: reader_headers

    assert_select "a[href=?]", reader_newsletters_path
  end
end
