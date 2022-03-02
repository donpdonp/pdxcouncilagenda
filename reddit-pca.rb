#!/usr/bin/env ruby
require 'bundler/setup'
require "httparty"
require 'json'

def access_token
  puts "access_token"
  HTTParty.post('https://ssl.reddit.com/api/v1/access_token',
              {:body => ["grant_type=password",
                         "username=#{@reddit['auth']['username']}",
                         "password=#{@reddit['auth']['password']}"].join('&'),
               :basic_auth => {:username => @reddit['auth']['httpuser'], 
                               :password => @reddit['auth']['httppass']},
               :headers => {"User-Agent" => "pdxcitycouncil-scraper"}
              }).parsed_response["access_token"]
end

def make_title(item)
  #["TOO_LONG", "this is too long (max: 300)", "title"]
  title = item['title'].match(/([^(]+)/).captures.first
  title = title[0,294]+" [#{item['number']}]"
end

def make_text(item)
  emergency = item['emergency'] ? "(this item takes effect immediately if passed)" : ""
  "Session #{item['session']} Item \\##{item['number']}\nBureau: #{item['bureau']}" + "\n\n" +
  item['title'] + "\n\n" + emergency + "\n\n" + item['link'] + "\n"
end

def api(path, token, params)
  HTTParty.post("https://oauth.reddit.com#{path}",
                {:headers => { 'Content-Type' => 'application/json',
                               'Authorization' => "bearer #{token}",
                               'User-Agent' => 'pdxcitycouncil-scraper'},
                 :query => params })
    puts "api success"
    return
end

def add_story(token, post)
  puts "Submitting..."
  post = api('/api/submit', token,
                                  {'api_type' => "json",
                                   'kind' => 'self',
                                   'sr' => "pdxcouncilagenda",
                                   'title' => make_title(post),
                                   'text' => make_text(post)} 
                       )
  #puts "#{post.parsed_response.inspect}"
  #{"json"=>{"errors"=>[], "data"=>{"url"=>"https://oauth.reddit.com/r/pdxcouncilagenda/comments/274cvy/portland_city_council_agenda/", "id"=>"274cvy", "name"=>"t3_274cvy"}}}
end


def load_posts
  posts = []
  url = "https://www.reddit.com/r/pdxcouncilagenda/new.json?limit=#{@reddit['limit']}"
  puts url
  data = HTTParty.get(url, {
               :headers => {"User-Agent" => "pdxcitycouncil-scraper"}
           }).parsed_response
  if data['error']
    puts "reddit error: #{data['message']}"
  else
    posts = data['data']['children']
    posts.each do |p| 
      match = p['data']['title'].match(/\[(\d+)\]/)
      p['data']['agenda_number'] = match.captures.first if match
    end
  end
  posts
end

@reddit = JSON.parse(File.read("reddit.json"))
clean = ARGV[0] == 'clean' if ARGV[0]
do_post = ARGV[0] == 'post' if ARGV[0]

puts "clean mode ON" if clean
puts "LIVE POST" if do_post

puts "loading r/pdxcouncilagenda posts"
posts = load_posts
puts "loaded #{posts.length} reddit posts"
story_ids = posts.map{|p|p['data']['agenda_number']}.compact

# agenda
puts "loading scraped council agenda items"
agenda = HTTParty.get('http://donp.org/pdxapi/pdx-council-agenda.json').parsed_response
puts "loaded #{agenda['items'].size} agenda items"
unposted = agenda['items'].reject{|item| story_ids.include?(item['number'])}
puts "#{unposted.size} unposted #{unposted.map{|p|p['number']}.sort}"

if story_ids.empty?
  puts "reddit load is empty. aborting early."
  exit
end

token = access_token()
puts "Reddit access token #{token}"

if clean
  story_ids.each do |id| 
    post = posts.select{|p| p['data']['agenda_number'] == id}.first
    rid = "#{post['kind']}_#{post['data']['id']}"
    puts "Deleting agenda #{id} reddit post #{rid}"
    del = api('/api/del', token, {"id" => rid})
    puts del.body
  end
end

if do_post
  unposted.each do |post|
    puts "Posting #{post['number']}"
    add_story(token, post)
  end
end

