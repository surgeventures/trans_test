#!/usr/bin/env ruby

require 'json'
require 'net/http'

# Base method for making all requests against CrowdIn API

def request(path, method: :get, type: 'application/json', body: nil, params: {})
  url = "https://fresha.crowdin.com/api/v2/#{path}"
  uri = URI(url)
  uri.query = URI.encode_www_form(params)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  token = ENV.fetch('CROWDIN_API_TOKEN')
  headers = {
    'Content-Type' => type,
    'Authorization' => "Bearer #{token}"
  }
  case method
  when :get
    req = Net::HTTP::Get.new(uri, headers)
  when :post
    req = Net::HTTP::Post.new(uri, headers)
  end

  if body
    if type == 'application/json' && body.is_a?(Hash)
      req.body = JSON.dump(body)
    else
      req.body = body
    end
  end
  res = http.request(req)

  if res.code.to_i < 400
    JSON.parse(res.body)
  else
    raise("#{method.to_s.upcase} #{url} failed (#{res.code}): #{res.body}")
  end
end

# Wrappers for specific API methods from https://support.crowdin.com/enterprise/api

def get_projects
  request("projects").fetch('data').map do |project|
    {
      id: project['data']['id'],
      name: project['data']['name']
    }
  end
end

def get_project_branches(project_id)
  request("projects/#{project_id}/branches").fetch('data').map do |branch|
    {
      id: branch['data']['id'],
      name: branch['data']['name']
    }
  end
end

def get_project_branch_directories(project_id, branch_id)
  request("projects/#{project_id}/directories", params: { "branchId" => branch_id, "recursion" => 1, "limit" => 500 }).fetch('data').map do |dir|
    {
      id: dir['data']['id'],
      name: dir['data']['name'],
      parent_id: dir['data']['parentId']
    }
  end
end

def add_storage(path)
  request("storages", method: :post, body: File.read(path), type: "text/plain").fetch('data').fetch('id')
end

# Getters that further wrap API calls and postprocess their results if needed

def get_project_id(name)
  project = get_projects().find {|project| project[:name] == name}
  project ? project.fetch(:id) : raise("Project not found: #{name}")
end

def get_project_branch_id(project_id, name)
  branch = get_project_branches(project_id).find {|branch| branch[:name] == name}
  branch ? branch.fetch(:id) : raise("Branch not found: #{name}")
end

def get_project_branch_directories_with_paths(project_id, branch_id)
  get_project_branch_directories(project_id, branch_id).map do |dir|
    dir.merge(path: get_directory_path(dirs, dir))
  end
end

def get_directory_path(dirs, dir)
  if dir[:parent_id]
    parent_dir = dirs.find {|idir| idir[:id] == dir[:parent_id]} || raise
    get_directory_path(dirs, parent_dir) + "/" + dir[:name]
  else
    dir[:name]
  end
end

def get_project_branch_directory_id(project_id, branch_id, path)
  dirs = get_project_branch_directories(project_id, branch_id)
  dirs_with_paths = map_dirs_paths(dirs)
  dir = dirs_with_paths.find {|dir| dir[:path] == path}
  dir ? dir.fetch(:id) : raise("Directory not found: #{name}")
end

def add_project_directory_file(project_id, directory_id, storage_id, name, export_pattern)
  request("projects/#{project_id}/files", method: :post, body: {
    "name" => File.basename(name),
    "storageId" => storage_id,
    "directoryId" => directory_id,
    "exportOptions" => {
      "exportPattern" => export_pattern
    }
  })
end

# Glue code for final operations

def upload_file(project_name, branch_name, source_filename, target_path, export_pattern)
  storage_id = add_storage(source_filename)
  puts "Storage ID (#{source_filename}): #{storage_id}"

  project_id = get_project_id(project_name)
  puts "Project ID (#{project_name}): #{project_id}"

  branch_id = get_project_branch_id(project_id, branch_name)
  puts "Branch ID (#{branch_name}): #{branch_id}"

  directory_id = get_project_branch_directory_id(project_id, branch_id, target_path)
  puts "Directory ID (#{target_path}): #{directory_id}"

  add_project_directory_file(project_id, directory_id, storage_id, source_filename, export_pattern)
end

# Main

upload_file(
  "Test GH",                                              # project name
  "master",                                               # branch name
  "apps/a/priv/gettext/new.pot",                          # source filename
  "a/priv/gettext",                                       # target directory
  "/a/priv/gettext/%two_letters_code%/LC_MESSAGES/new.po" # export pattern
)
