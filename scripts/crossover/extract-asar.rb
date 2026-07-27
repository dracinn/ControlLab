# frozen_string_literal: true

# Minimal, dependency-free ASAR extractor for disposable CrossOver diagnostics.
# It preserves unpacked native modules by copying them from app.asar.unpacked.

require "fileutils"
require "json"

archive_path, destination = ARGV
abort("usage: extract-asar.rb <app.asar> <destination>") unless archive_path && destination

archive_path = File.expand_path(archive_path)
destination = File.expand_path(destination)
unpacked_root = "#{archive_path}.unpacked"

File.open(archive_path, "rb") do |archive|
  sizes = archive.read(16).unpack("V4")
  header = JSON.parse(archive.read(sizes.fetch(3)))
  data_offset = 8 + sizes.fetch(1)

  extract = lambda do |entries, relative_directory|
    entries.each do |name, entry|
      relative_path = File.join(relative_directory, name)
      output_path = File.join(destination, relative_path)

      if entry.key?("files")
        FileUtils.mkdir_p(output_path)
        extract.call(entry.fetch("files"), relative_path)
      elsif entry.key?("link")
        FileUtils.mkdir_p(File.dirname(output_path))
        File.symlink(entry.fetch("link"), output_path)
      elsif entry["unpacked"]
        FileUtils.mkdir_p(File.dirname(output_path))
        FileUtils.cp(File.join(unpacked_root, relative_path), output_path)
      else
        FileUtils.mkdir_p(File.dirname(output_path))
        archive.seek(data_offset + entry.fetch("offset").to_i)
        File.binwrite(output_path, archive.read(entry.fetch("size")))
        File.chmod(0o755, output_path) if entry["executable"]
      end
    end
  end

  FileUtils.mkdir_p(destination)
  extract.call(header.fetch("files"), "")
end

puts destination
