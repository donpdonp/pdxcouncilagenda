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
    bill['number'] = number
    break
  end
  agenda_row.css('div.council-document__title').each do |node|
    parts = node.text.split("\n")
    title = parts[0].strip.delete_prefix("*")
    bill['title'] = title
    kind = parts[1].strip.delete_prefix("(").delete_suffix(")")
    bill['kind'] = kind
    path = node.css('a').attr('href')
    link = "https://#{Uri.host}#{path}"
    bill['link'] = link
  end
  agenda_row.css('div.field--name-field-agenda-item-disposition div.field__item').each do |node|
    bill['disposition'] = node.text
  end
  agenda_row.css('div.field--name-field-bureau div.field__item').each do |node|
    bill['bureau'] = node.text
  end
  votes = agenda_row.css('div.field--name-field-votes div.field__item').map do |node| 
    parts = node.text.split(" ").map{|n| n.strip}
    title = parts.shift
    vote = parts.pop
    { :title => title, :name => parts.join(" "), :vote => vote }
  end
  STDERR.puts(votes)

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
        bill['session'] = Time.parse(agenda_date).localtime.strftime("%Y-%m-%d %-l:%M%p")
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
