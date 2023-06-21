#!/usr/bin/env ruby
require 'bundler/setup'
require "httparty"
require 'json'

def access_token
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
  "Session #{item['session']} " + "|" + "Item \\##{item['number']} " + "|" + "#{item['bureau']}" + "|" + "#{item['disposition']}" + "\n\n"  +
  item['title'] + "\n\n" + emergency + "\n\n" + 
  item['link'] + "\n"
end

def make_vote_comment(item)
  comment = "Disposition: #{item['disposition']}\n\n"
  comment += item['votes'].map do |v|
    "  * #{v['title']} #{v['name']} #{v['vote']}"
  end.join("\n\n")
  comment
end

def api(path, token, params)
  HTTParty.post("https://oauth.reddit.com#{path}",
                {:headers => { 'Content-Type' => 'application/json',
                               'Authorization' => "bearer #{token}",
                               'User-Agent' => 'pdxcitycouncil-scraper'},
                 :query => params })
end

def add_story(token, post)
  api('/api/submit', token,
                                  {'api_type' => "json",
                                   'kind' => 'self',
                                   'sr' => "pdxcouncilagenda",
                                   'title' => make_title(post),
                                   'text' => make_text(post)} ).parsed_response
  #puts "#{post.parsed_response.inspect}"
  #{"json"=>{"errors"=>[], "data"=>{"url"=>"https://oauth.reddit.com/r/pdxcouncilagenda/comments/274cvy/portland_city_council_agenda/", "id"=>"274cvy", "name"=>"t3_274cvy"}}}
end

def add_comment(token, post, comment)
  api('/api/comment', token,
                                  {'api_type' => "json",
                                   'thing_id' => post['name'],
                                   'text' => comment}).parsed_response
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
      match = p['data']['title'].match(/\[([0-9 -]+)\]/)
      p['data']['agenda_number'] = match.captures.first if match
    end
  end
  posts.map{|p| p['data']}
end

def load_comments(post)
  url = "https://www.reddit.com/r/pdxcouncilagenda/comments/#{post['id']}.json"
  puts url
  data = HTTParty.get(url, {
               :headers => {"User-Agent" => "pdxcitycouncil-scraper"}
           }).parsed_response
  if !data.is_a?(Array)
    puts "reddit error: #{data['message']}"
  else
    data[1]['data']['children'].map do |comment|
      if comment['kind'] == 't1'
        comment['data']
      end
    end
  end
#{"subreddit_id"=>"t5_31utx", "approved_at_utc"=>nil, "author_is_blocked"=>false, "comment_type"=>nil, "awarders"=>[], "mod_reason_by"=>nil, "banned_by"=>nil, "author_fl
#air_type"=>"text", "total_awards_received"=>0, "subreddit"=>"pdxcouncilagenda", "author_flair_template_id"=>nil, "likes"=>nil, "replies"=>"", "user_reports"=>[], "saved"
#=>false, "id"=>"i5n3nhp", "banned_at_utc"=>nil, "mod_reason_title"=>nil, "gilded"=>0, "archived"=>false, "collapsed_reason_code"=>nil, "no_follow"=>true, "author"=>"donp
#donp", "can_mod_post"=>false, "created_utc"=>1650561868.0, "send_replies"=>true, "parent_id"=>"t3_u4bwbn", "score"=>1, "author_fullname"=>"t2_1zlsy", "approved_by"=>nil,
# "mod_note"=>nil, "all_awardings"=>[], "collapsed"=>false, "body"=>"comment", "edited"=>false, "top_awarded_type"=>nil, "author_flair_css_class"=>nil, "name"=>"t1_i5n3nh
#p", "is_submitter"=>false, "downs"=>0, "author_flair_richtext"=>[], "author_patreon_flair"=>false, "body_html"=>"&lt;div class=\"md\"&gt;&lt;p&gt;comment&lt;/p&gt;\n&lt;
#/div&gt;", "removal_reason"=>nil, "collapsed_reason"=>nil, "distinguished"=>nil, "associated_award"=>nil, "stickied"=>false, "author_premium"=>false, "can_gild"=>true, "
#gildings"=>{}, "unrepliable_reason"=>nil, "author_flair_text_color"=>nil, "score_hidden"=>false, "permalink"=>"/r/pdxcouncilagenda/comments/u4bwbn/accept_the_2021_annual
#_report_of_the_north_and/i5n3nhp/", "subreddit_type"=>"restricted", "locked"=>false, "report_reasons"=>nil, "created"=>1650561868.0, "author_flair_text"=>nil, "treatment
#_tags"=>[], "link_id"=>"t3_u4bwbn", "subreddit_name_prefixed"=>"r/pdxcouncilagenda", "controversiality"=>0, "depth"=>0, "author_flair_background_color"=>nil, "collapsed_
#because_crowd_control"=>nil, "mod_reports"=>[], "num_reports"=>nil, "ups"=>1}
end


@reddit = JSON.parse(File.read("reddit.json"))
clean = ARGV[0] == 'clean' if ARGV[0]
do_post = ARGV[0] == 'post' if ARGV[0]

puts "clean mode ON" if clean
puts "LIVE POST" if do_post

puts "loading r/pdxcouncilagenda posts"
posts = load_posts
puts "loaded #{posts.length} reddit posts"
story_ids = {}
posts.each do |p|
  if p['agenda_number']
    story_ids[p['agenda_number']] = p
  end
end

if story_ids.empty?
  puts "reddit posts dont match agenda numbers. aborting early."
  exit
end

# agenda
puts "loading scraped council agenda items"
agenda_json = "https://donp.org/pdxapi/pdx-council-agenda.json"
puts agenda_json
agenda = HTTParty.get(agenda_json).parsed_response
puts "loaded #{agenda['items'].size} agenda items"

unposted = agenda['items'].reject{|item| story_ids.include?(item['number'])}
puts "#{unposted.size} unposted #{unposted.map{|p|p['number']}.sort}"

begin
  token = access_token()
rescue e
  puts "reddit access token request failed: #{e}"
  exit
end

if clean
  story_ids.each do |post| 
    kind = 't3' #always t3
    rid = "#{kind}_#{post['id']}"
    puts "Deleting agenda #{id} reddit post #{rid}"
    del = api('/api/del', token, {"id" => rid})
    puts del.body
  end
end

if do_post
  unposted.each do |post|
    result = add_story(token, post)
    puts "Posting #{post['number']} #{result}"
  end
end

voted = agenda['items'].select{|item| item['votes'].length > 0}
voted.each do |v|
  post = story_ids[v['number']]
  if post 
    comments = load_comments(post)
    puts "##{v['number']} #{v['votes'].length} council votes. #{comments.length} reddit comments."
    vote_comment = comments.select do |comment|
      yn = comment['body'].match(/^Disposition/) && comment['author'] == 'pdxapibot'
      puts "#{post['id']} #{comment['author']} #{comment['body']} #{yn}"
      yn
    end
    if vote_comment.empty?
      if do_post
        result = add_comment(token, post, make_vote_comment(v))
        if result['json']['errors'].length > 0
          puts "add_comment error #{result['json']['errors']}"
        end
      end
    end
  else
    puts "Warning: no reddit post for agenda #{v['number']}"
  end
end


