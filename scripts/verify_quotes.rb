#!/usr/bin/env ruby
# frozen_string_literal: true

# Check that every quote in a review appears in the book's text.
#
# Usage:
#   ruby scripts/verify_quotes.rb src/_books/<review>.md path/to/text-dir
#
# `text-dir` holds one .txt file per chapter (see scripts/epub_to_text.rb).
# Every blockquote line (starting `>`) and every inline "double-quoted" string
# in the review body is split at ellipses (`…` or `...`) and bracketed edits
# (`[like this]`), and each remaining fragment is searched for, case- and
# punctuation-style-insensitively, in all of the text files. The output is one
# OK/MISS entry per quote with the file:line of each fragment.
#
# This only proves the wording exists somewhere in the book. It does not
# check order, context, or whether a paraphrase is fair; that is judgement for
# a person or the book-verifier. Scare quotes and the author's own terms in
# quotation marks (for example a series label) will show as MISS; that is
# expected and not an error in the review.
#
# Exit status: 0 when every fragment is found, 1 when any is missing.

MIN_FRAGMENT_LENGTH = 4
PUNCTUATION_EDGES = %( ,.;:'"‘’“”).chars.freeze

def usage_and_exit
  warn 'usage: ruby scripts/verify_quotes.rb <review.md> <text-dir>'
  exit 2
end

def normalise(text)
  text
    .tr("‘’", "''")
    .tr("“”", '""')
    .tr("–—", '--')
    .delete('*_')
    .gsub(/\s+/, ' ')
    .strip
    .downcase
end

def review_body(path)
  content = File.read(path, encoding: 'UTF-8')
  match = content.match(/\A---\n.*?\n---\n/m)
  match ? match.post_match : content
end

def extract_quotes(body)
  quotes = []
  body.each_line.with_index(1) do |line, number|
    line = line.chomp
    if line.start_with?('>')
      quotes << [number, :block, line.sub(/\A>\s*/, '')]
    else
      line.scan(/["“]([^"“”]+)["”]/) { |match| quotes << [number, :inline, match.first] }
    end
  end
  quotes
end

def fragments(quote)
  quote.gsub(/\[[^\]]*\]/, '')
       .split(/…|\.\.\./)
       .map { |part| part.strip.gsub(/\A[#{Regexp.escape(PUNCTUATION_EDGES.join)}]+|[#{Regexp.escape(PUNCTUATION_EDGES.join)}]+\z/, '') }
       .select { |part| part.length >= MIN_FRAGMENT_LENGTH }
end

def load_corpus(dir)
  corpus = []
  Dir.glob(File.join(dir, '*.txt')).sort.each do |file|
    File.foreach(file, encoding: 'UTF-8').with_index(1) do |line, number|
      corpus << [File.basename(file), number, normalise(line)]
    end
  end
  corpus
end

review, text_dir = ARGV
usage_and_exit unless review && text_dir && File.file?(review) && File.directory?(text_dir)

corpus = load_corpus(text_dir)
abort "no .txt files found in #{text_dir}" if corpus.empty?

quotes = extract_quotes(review_body(review))
missing = 0

quotes.each do |number, kind, quote|
  results = fragments(quote).map do |fragment|
    needle = normalise(fragment)
    [fragment, corpus.select { |_file, _line, text| text.include?(needle) }.first(2)]
  end

  ok = !results.empty? && results.all? { |_fragment, hits| !hits.empty? }
  missing += 1 unless ok
  puts "#{ok ? 'OK  ' : 'MISS'} body-line #{number} [#{kind}]"
  results.each do |fragment, hits|
    where = hits.empty? ? 'NOT FOUND' : hits.map { |file, line, _text| "#{file}:#{line}" }.join(', ')
    puts "      #{fragment[0, 90].inspect} -> #{where}"
  end
end

puts
puts "TOTAL #{quotes.size} quotes; #{missing} with a missing fragment"
exit(missing.zero? ? 0 : 1)
