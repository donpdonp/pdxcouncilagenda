#!/usr/bin/env ruby
require 'bundler/setup'
require 'nokogiri'
require 'open-uri'
require 'json'
require 'time'

url = ARGV[0] || "https://www.portland.gov/council/agenda" 
Uri = URI::parse(url)
STDERR.puts Uri

def parse_bill(agenda_row)
  bill = {}
  agenda_row.css('h4').each do |id|
    number = id.text.strip
    STDERR.puts("id #{number}")
    bill['number'] = number
    break
  end
  agenda_row.css('div.council-document__title').each do |id|
    parts = id.text.split("\n")
    title = parts[0].strip
    bill['title'] = title
    STDERR.puts("title #{title}")
    dept = parts[1].strip
    STDERR.puts("dept #{dept}")
    path = id.css('a').attr('href')
    link = "https://#{Uri.host}#{path}"
    bill['link'] = link
    STDERR.puts("link #{link}")
  end
  # bill.merge!(:time_certain => item_date)
  # bill.merge!(:link => "https://#{uri.host}/#{citypdf.attributes['href']}") if citypdf
  # bill.merge!({:emergency => true}) if emergency
  bill
end

def tableread(tablerow, agenda_date) 
  items = []
  tablerow.css("div.view-admin-agenda-items").each do |row|
    row.css('div.relation--type-agenda-item').each do |item|
        bill = parse_bill(item)
        bill['session'] = Time.parse(agenda_date).localtime
        items << bill if bill
    end
  end
  items
end

doc = Nokogiri::HTML(URI.open(url).read)

items = []
doc.css("div.relation--type-council-session").each do |row|
  agenda_date = row.css('div.session-meta time').attr('datetime').text
  if agenda_date then
    STDERR.puts "Section: #{agenda_date}"
    tableitems = tableread(row, agenda_date)
    STDERR.puts "parsing section #{agenda_date} -> #{tableitems.length} items found"
    items += tableitems
  end
end

agenda = {
  :source => url,
  :scrape_date => Time.now,
  :items => items
}
puts JSON.pretty_generate(agenda)
