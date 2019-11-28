#!/usr/bin/env ruby

require 'json'
require 'net/http'

# API request builder

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

# API methods (https://support.crowdin.com/enterprise/api)

def get_projects
  request("projects").fetch('data').map do |project|
    {
      id: project['data']['id'],
      name: project['data']['name']
    }
  end
end

def get_branches(project_id)
  request("projects/#{project_id}/branches").fetch('data').map do |branch|
    {
      id: branch['data']['id'],
      name: branch['data']['name']
    }
  end
end

def get_directories(project_id, branch_id = nil)
  params = {}
  params.merge!("branchId" => branch_id, "recursion" => 1) if branch_id

  dirs = loop_all_pages do |page_params|
    request("projects/#{project_id}/directories", params: params.merge(page_params)).fetch('data')
  end

  dirs = dirs.map do |dir|
    {
      id: dir['data']['id'],
      name: dir['data']['name'],
      parent_id: dir['data']['parentId'],
      branch_id: dir['data']['branchId']
    }
  end

  if branch_id == nil
    dirs = dirs.select do |dir|
      !dir[:branch_id]
    end
  end

  dirs = dirs.map do |dir|
    {
      id: dir[:id],
      name: dir[:name],
      path: lookup_directory_path(dirs, dir)
    }
  end

  dirs
end

def lookup_directory_path(dirs, dir)
  if dir[:parent_id]
    parent_dir = dirs.find {|idir| idir[:id] == dir[:parent_id]} || raise
    lookup_directory_path(dirs, parent_dir) + "/" + dir[:name]
  else
    dir[:name]
  end
end

def add_directory(project_id, parent_dir, name)
  body = { "name" => name }
  body.merge!({ "parentId" => parent_dir[:id] }) if parent_dir

  dir = request("projects/#{project_id}/directories", method: :post, body: body)

  {
    id: dir['data']['id'],
    name: dir['data']['name'],
    parent_id: dir['data']['parentId'],
    branch_id: dir['data']['branchId'],
    path: parent_dir ? parent_dir[:path] + '/' + name : name
  }
end

def get_files(project_id, branch_id = nil)
  params = {}
  params.merge!("branchId" => branch_id, "recursion" => 1) if branch_id

  files = loop_all_pages do |page_params|
    request("projects/#{project_id}/files", params: params.merge(page_params)).fetch('data')
  end

  files = files.map do |file|
    {
      id: file['data']['id'],
      name: file['data']['name'],
      directory_id: file['data']['directoryId'],
      branch_id: file['data']['branchId']
    }
  end

  if branch_id == nil
    files = files.select do |file|
      !file[:branch_id]
    end
  end

  files = files.map do |file|
    {
      id: file[:id],
      name: file[:name],
      directory_id: file[:directory_id]
    }
  end

  files
end

def add_file(project_id, directory_id, storage_id, name, export_pattern = nil)
  body = {
    "name" => File.basename(name),
    "storageId" => storage_id,
    "directoryId" => directory_id
  }

  body.merge!({
    "exportOptions" => {
      "exportPattern" => export_pattern
    }
  }) if export_pattern

  request("projects/#{project_id}/files", method: :post, body: body)
end

def update_file(project_id, file_id, storage_id)
  body = {
    "storageId" => storage_id
  }

  request("projects/#{project_id}/files/#{file_id}/update", method: :post, body: body)
end

def add_storage(path)
  request("storages", method: :post, body: File.read(path), type: "text/plain")
    .fetch('data')
    .fetch('id')
end

# Pagination

def loop_all_pages
  items = []
  page = 0
  limit = 10

  begin
    params = params = { "offset" => limit * page, "limit" => limit }
    new_items = yield(params)
    items += new_items
    page += 1
  end while new_items.length == limit

  items
end

# Misc glue code

def get_project_id(name)
  project = get_projects().find {|project| project[:name] == name}
  project ? project.fetch(:id) : raise("Project not found: #{name}")
end

def get_branch_id(project_id, name)
  branch = get_branches(project_id).find {|branch| branch[:name] == name}
  branch ? branch.fetch(:id) : raise("Branch not found: #{name}")
end

def get_directory_id(project_id, branch_id, path)
  dirs = get_directories(project_id, branch_id)
  dir = dirs.find {|dir| dir[:path] == path}
  dir ? dir.fetch(:id) : raise("Directory not found: #{path}")
end

def get_or_add_path(project_id, path)
  dirs = get_directories(project_id)

  path_it = path
  base_dir = nil
  while !base_dir && path_it != '.'
    base_dir = dirs.find {|dir| dir[:path] == path_it}
    path_it = File.dirname(path_it)
  end

  dir = create_dirs_recursive(project_id, base_dir, path)
  dir ? dir.fetch(:id) : raise("Directory not found: #{path}")
end

def create_dirs_recursive(project_id, base_dir, path)
  base_path = base_dir && base_dir[:path]
  return base_dir if base_path == path

  missing_path = base_path ? path.sub("#{base_path}/", '') : path
  next_base_dir_name = missing_path.split("/").first
  next_base_dir = add_directory(project_id, base_dir, next_base_dir_name)

  puts "Created directory #{next_base_dir[:path]}"

  create_dirs_recursive(project_id, next_base_dir, path)
end

def add_or_update_file(project_id, directory_id, storage_id, name, export_pattern = nil)
  files = get_files(project_id)
  existing_file = files.find do |file|
    file[:directory_id] == directory_id && file[:name] == File.basename(name)
  end

  if existing_file
    update_file(project_id, existing_file[:id], storage_id)
  else
    add_file(project_id, directory_id, storage_id, name, export_pattern)
  end
end

# Interface

def upload_file(project_name, source_filename, target_path)
  storage_id = add_storage(source_filename)
  puts "Storage ID (#{source_filename}): #{storage_id}"

  project_id = get_project_id(project_name)
  puts "Project ID (#{project_name}): #{project_id}"

  directory_id = get_or_add_path(project_id, target_path)
  puts "Directory ID (#{target_path}): #{directory_id}"

  add_or_update_file(project_id, directory_id, storage_id, source_filename)
end

def upload_file_branch(project_name, branch_name, source_filename, target_path, export_pattern)
  storage_id = add_storage(source_filename)
  puts "Storage ID (#{source_filename}): #{storage_id}"

  project_id = get_project_id(project_name)
  puts "Project ID (#{project_name}): #{project_id}"

  branch_id = get_branch_id(project_id, branch_name)
  puts "Branch ID (#{branch_name}): #{branch_id}"

  directory_id = get_directory_id(project_id, branch_id, target_path)
  puts "Directory ID (#{target_path}): #{directory_id}"

  add_or_update_file(project_id, directory_id, storage_id, source_filename, export_pattern)
end

# Main

upload_file(
  "Test GH",                         # project name
  "apps/a/priv/gettext/default.pot", # source filename
  "db"                               # target directory
)

# upload_file_branch(
#   "Test GH",                                              # project name
#   "master",                                               # branch name
#   "apps/a/priv/gettext/new.pot",                          # source filename
#   "a/priv/gettext",                                       # target directory
#   "/a/priv/gettext/%two_letters_code%/LC_MESSAGES/new.po" # export pattern
# )
