#!/usr/bin/env ruby
require 'bundler/setup'
require 'nokogiri'
require 'open-uri'
require 'json'
require 'time'

URL_HOST = 'https://www.portlandoregon.gov'

def parse_bill(agenda_row, agenda_date)
  bill = {}
  link = agenda_row.css('strong')[0]
  link_text = link.text
  number_match = link_text.match(/^[[:space:]]*(\*)?(\d+)/)
  return if !number_match
  emergency = !number_match.captures[0].nil?
  number = number_match.captures[1]
  link.remove
  title = agenda_row.text.gsub(/^[[:space:]]+/,'')

  time_certain_match = title.match(/^(TIME.CERTAIN:.(\d+:\d+.\w\w).)/)
  if time_certain_match
    item_date = Time.parse("#{agenda_date.to_date} #{time_certain_match[2]}")
    title = title[time_certain_match[1].length + 2, title.length]
    bill.merge!(:time_certain => item_date)
  end

  bill.merge!(:link => URL_HOST ,
              :number => number,
              :session => agenda_date,
              :title => title)
  bill.merge!({:emergency => true}) if emergency
  bill
end

def tableread(doc, tablename) 
  items = []
  agenda_date = nil
  doc.css("section#main-content table.#{tablename} tbody td").each do |row|
    row.css('p strong').each do |head|
      date_match = head.text.match(/\d+:\d+ \w\w, \w+ [\d-]+, 20\d\d/)
      if date_match
        clean_date = date_match[0].gsub(/-\d+/, '')
        agenda_date = Time.parse(clean_date)
      end
    end


    if agenda_date
      p = row.css('p').first
      if p && (p.css('strong').length > 0)
        bill = parse_bill(p, agenda_date)
        items << bill if bill
      end
    end
  end
  items
end

url = URL_HOST + '/auditor/index.cfm?c=26997'
STDERR.puts url
doc = Nokogiri::HTML(open(url).read)

items = []
doc.css("section#main-content table").each do |row|
  classTableName = row.attributes['class']
  tableitems = tableread(doc, classTableName )
  STDERR.puts "parsing table.#{classTableName} -> #{tableitems.length} items found"
  items += tableitems
end

agenda = {
  :source => url,
  :scrape_date => Time.now,
  :items => items
}
puts JSON.pretty_generate(agenda)
