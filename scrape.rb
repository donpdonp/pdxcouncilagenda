#!/usr/bin/env ruby
require 'bundler/setup'
require 'nokogiri'
require 'open-uri'
require 'json'
require 'time'

def assume_date(tablename)
  dayword =  case tablename
  when 'bluetable'
    'wednesday'
  when 'greentable'
    'wednesday'
  when 'goldtable'
    'thursday'
  end
  t = Time.now
  7.times do 
    break if t.public_send(dayword+'?')
    t += 60*60*24
  end
  t
end

def parse_bill(agenda_row, agenda_date, uri)
  bill = {}
  title = agenda_row.text.gsub(/[[:space:]]/, ' ').strip #replace non-breaking spaces
  agenda_number_match = title.match(/^(\s*(\*)?(\d+)(\s+TIME.CERTAIN:.(\d+:\d+.\w\w).)?)/)
  agenda_number = agenda_number_match[3]
  emergency = !!agenda_number_match[2]
  if agenda_number_match[5]
    item_date = Time.parse("#{agenda_date.to_date} #{agenda_number_match[5]}")
    bill.merge!(:time_certain => item_date)
  end
  title = title[agenda_number_match[1].length + 2, title.length]

  bill.merge!( :number => agenda_number,
              :session => agenda_date,
              :title => title)
  citypdf = agenda_row.css('strong a')[0]
  bill.merge!(:link => "https://#{uri.host}/#{citypdf.attributes['href']}") if citypdf
  bill.merge!({:emergency => true}) if emergency
  bill
end

def tableread(tablerow, uri, agenda_date) 
  items = []
  tablerow.css("tbody tr").each do |row|
    row.css('td').each do |head|
      unless agenda_date
        date_match = head.text.match(/\d+:\d+ \w\w, \w+ [\d-]+, 20\d\d/)
        if date_match
          clean_date = date_match[0].gsub(/-\d+/, '')
          agenda_date = Time.parse(clean_date)
        else
          #agenda_date = assume_date(tablename)
          #STDERR.puts "parse warning: table row header #{agenda_date.inspect} has no parsable date"
        end
      end
    end

    if agenda_date
      p = row.css('p').first
      if p && (p.css('strong').length > 0)
        bill = parse_bill(p, agenda_date, uri)
        items << bill if bill
      end
    end
  end
  items
end

def datefind(text)
  match = text.match(/(\w+ \d+)([-\d]+)?(, 20\d\d)/)
  if match
    month_day = "#{match[1]}#{match[3]}"
    Date.parse(month_day)
  end
end

url = ARGV[0] || 'https://www.portlandoregon.gov/auditor/index.cfm?c=26997'
uri = URI::parse(url)
STDERR.puts uri
doc = Nokogiri::HTML(URI.open(url).read)
agenda_date = nil

doc.css("h2.content-center").each do |row|
  agenda_date ||= datefind(row.text)
end
STDERR.puts "Agenda Date: #{agenda_date}"

items = []
doc.css("section#main-content table").each do |row|
  header_text = row.css('tr:first-child h2').text
  STDERR.puts "Section: #{header_text}"
  header_date = datefind(header_text)
  classTableName = row.attributes['class']
  tableitems = tableread(row, uri, header_date)
  STDERR.puts "parsing table.#{classTableName} -> #{tableitems.length} items found"
  items += tableitems
end

agenda = {
  :source => url,
  :scrape_date => Time.now,
  :items => items
}
puts JSON.pretty_generate(agenda)
