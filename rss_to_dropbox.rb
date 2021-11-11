#!/usr/bin/env ruby

# Usage:
# ruby rss_to_dropbox.rb <rss_url>

require 'dotenv/load'

require 'down'
require 'dropbox_api'
require 'fileutils'
require 'nokogiri'
require 'open-uri'

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
podcast_episodes = doc.css('rss channel item')

puts "Found #{podcast_episodes.count} episodes for podcast #{podcast_title}"

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

podcast_episodes.each_with_index do |episode, idx|
  # TODO: assuming .mp3 here
  #filename = "#{sanitize_filename(episode.css('title').inner_text)}.mp3"

  # download episode to local, upload to Dropbox, delete from local
  url = episode.css('enclosure').attribute('url').value
  # TODO: stream directly via https://github.com/janko/down/issues/18#issuecomment-371051686
  tempfile = Down.download(url)
  client.upload_by_chunks(
    # "#{folder_path}/#{tempfile.original_filename}",
    "#{folder_path}/#{idx+1}.mp3",
     tempfile,
     chunk_size:  100 * 1024 * 1024
  )
  tempfile.close

  puts "🎉🎉🎉 Uploaded to #{folder_path}/#{tempfile.original_filename}...sleeping before continuing"
  sleep 10
  puts ''
end
