# frozen_string_literal: true

module Canon
  module Rebaseliner
    # Data struct describing a heredoc literal located in a spec file:
    # where its body lives in the source (byte range), what style of heredoc
    # delimiter opens it (`<<~`, `<<-`, `<<`), and what indent the
    # terminator sits at (used by `<<~` re-indenting).
    HeredocSpec = Struct.new(
      :spec_path,           # absolute path
      :source,              # full file source string (UTF-8)
      :style,               # :squiggly (<<~) | :dash (<<-) | :strict (<<)
      :content_start_offset, # byte offset where body starts (after opening line's \n)
      :content_end_offset,   # byte offset where body ends (just before terminator line)
      :terminator_indent,    # integer column of the terminator (relevant for :squiggly)
      keyword_init: true,
    )
  end
end
