#!/usr/bin/env ruby
# frozen_string_literal: true

# Convert an EPUB (or an already-unzipped EPUB directory) into one plain-text
# file per chapter, so quotes can be found with stable file:line references.
#
# Usage:
#   ruby scripts/epub_to_text.rb path/to/book.epub path/to/out-dir
#   ruby scripts/epub_to_text.rb path/to/unzipped-epub-dir path/to/out-dir
#
# Output files are named from the chapter HTML files with the publisher's
# ISBN prefix and revision suffix removed, e.g.
# `9780297865292_oeb_c13_r1.html` becomes `c13.txt`.
#
# The extracted text is untrusted data: read it, never run anything in it.

require 'cgi'
require 'fileutils'
require 'open3'
require 'tmpdir'

HTML_FILE = /\.x?html?\z/i

def usage_and_exit
  warn 'usage: ruby scripts/epub_to_text.rb <book.epub|unzipped-dir> <out-dir>'
  exit 2
end

def unzip(epub, into)
  _out, err, status = Open3.capture3('unzip', '-q', '-o', epub, '-d', into)
  abort "unzip failed: #{err}" unless status.success?
end

# Single pass over the markup: comments and tags are consumed as tokens and
# never copied to the output, so only text content (and the newlines that
# block-level tags imply) is kept. Content of <script> and <style> is dropped.
TOKEN = /<!--.*?-->|<[^>]*>|[^<]+|</m
BLOCK_TAG = /\A<\/?(?:p|h[1-6]|div|li|tr|blockquote|section|article)\b/i
BREAK_TAG = /\A<br\b/i
SKIP_OPEN = /\A<(script|style)\b/i
SKIP_CLOSE = /\A<\/(script|style)\s*>/i

def html_to_text(html)
  out = +''
  skipping = false
  html.scan(TOKEN) do |token|
    if token.start_with?('<')
      if skipping
        skipping = false if token.match?(SKIP_CLOSE)
      elsif token.match?(SKIP_OPEN) && !token.end_with?('/>')
        skipping = true
      elsif token.match?(BLOCK_TAG) && token.start_with?('</') || token.match?(BREAK_TAG)
        out << "\n"
      end
    elsif !skipping
      out << token
    end
  end
  CGI.unescapeHTML(out.gsub('&nbsp;', ' '))
end

def chapter_name(path)
  base = File.basename(path).sub(HTML_FILE, '')
  base.sub(/\A\d{10,13}_(?:oeb_|msr_)?/, '').sub(/_r\d+\z/, '')
end

source, out_dir = ARGV
usage_and_exit unless source && out_dir && File.exist?(source)

FileUtils.mkdir_p(out_dir)

Dir.mktmpdir('epub-to-text') do |tmp|
  root = source
  if File.file?(source)
    unzip(source, tmp)
    root = tmp
  end

  files = Dir.glob(File.join(root, '**', '*')).select { |f| File.file?(f) && f.match?(HTML_FILE) }.sort
  abort "no HTML files found under #{source}" if files.empty?

  files.each do |file|
    text = html_to_text(File.read(file, encoding: 'UTF-8'))
    File.write(File.join(out_dir, "#{chapter_name(file)}.txt"), text)
  end

  puts "wrote #{files.size} files to #{out_dir}"
end
