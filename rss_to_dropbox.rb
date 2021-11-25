#!/usr/bin/env ruby

# Usage:
# ruby rss_to_dropbox.rb <rss_url> [<start_idx>] [<end_idx>]
# TODO:
#   - start, end idx args
#   - total count arg

require 'dotenv/load'

require 'down'
require 'dropbox_api'
require 'fileutils'
require 'nokogiri'
require 'open-uri'
require 'ruby-progressbar'

require 'pry'

# from https://github.com/rubyworks/facets/blob/master/lib/core/facets/file/sanitize.rb
def sanitize_filename(filename)
  filename = File.basename(filename.gsub("\\", "/")) # work-around for IE
  filename.gsub!(/[^a-zA-Z0-9\.\-\+_]/,"_")
  filename = "_#{filename}" if filename =~ /^\.+$/
  filename
end

rss_url = ARGV[0]
throw 'No RSS URL was provided' if !rss_url

doc = Nokogiri::XML(URI.open(rss_url))

podcast_title = sanitize_filename(doc.css('rss > channel > title').inner_text)
podcast_episodes = doc.css('rss channel item').reverse # RSS in descending order
start_idx = (ARGV[1] || 0).to_i
end_idx = (ARGV[2] || podcast_episodes.count - 1).to_i

puts ''
puts "Found #{podcast_episodes.count} total episodes for podcast #{podcast_title}"
puts "Transferring episodes between #{start_idx} and #{end_idx}"
puts ''

# initialize Dropbox
access_token = ENV['DROPBOX_ACCESS_TOKEN']
client = DropboxApi::Client.new(access_token)

# create folder in Dropbox if it doesn't exist already
folder_path = "/Podcasts/#{podcast_title}"

begin
  client.create_folder(folder_path)
rescue DropboxApi::Errors::FolderConflictError
  puts "Folder named #{podcast_title} already exists - not creating!"
end

temp_folder_path = "./.temp/#{podcast_title}"
FileUtils.mkdir_p(temp_folder_path)

# get list of files in folder to prevent redownloads
folder_data = client.list_folder(folder_path)
title_hash = folder_data.entries.map { |i| [i.name, true] }.to_h

skipped = []

podcast_episodes[start_idx..end_idx].each_with_index do |episode, idx|
  begin
    # TODO: assuming .mp3 here
    #filename = "#{sanitize_filename(episode.css('title').inner_text)}.mp3"

    url = episode.css('enclosure').attribute('url').value
    # TODO: stream directly via https://github.com/janko/down/issues/18#issuecomment-371051686

    total_size = 0
    progressbar = ProgressBar.create(title: 'Progress')
    tempfile = Down.download(
      url,
      content_length_proc: -> (content_length) { total_size = content_length },
      progress_proc: lambda do |progress|
        break if progress == total_size

        progressbar.progress = (progress.to_f / total_size) * 10
      end
    )

    # TODO: better file naming
    # filename = "#{folder_path}/#{idx+1}.mp3",
    filename = "#{folder_path}/#{tempfile.original_filename}"

    puts ''
    puts "Starting upload to #{filename}"

    client.upload_by_chunks(
      filename,
      tempfile,
      chunk_size:  100 * 1024 * 1024
    )
    tempfile.close

    puts ''
    puts "🎉🎉🎉 Uploaded to #{folder_path}/#{filename}"
    puts ''
  rescue StandardError => e
    puts "⚠️ Could not save episode #{idx}: #{e}"
    skipped.push(idx);
  end
end

if !skipped.empty?
  puts "Skipped #{skipped} -- try redownloading some other time, ya dumb!"
end
