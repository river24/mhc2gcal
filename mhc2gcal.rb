#!/usr/bin/env ruby
# -*- ruby -*-

## mhc2gcal
## Copyright (C) 2007 Nao Kawanishi <river2470@gmail.com>
## Author: Nao Kawanishi <river2470@gmail.com>

## "mhc2ical" is base code of mhc2gcal
## Original author: Yojiro UO <yuo@iijlab.net>
## "today" is base code of mhc2ical
## Original author: Yoshinari Nomura <nom@quickhack.net>

## "ol2gcal" is also base code of mhc2gcal
## Original author: <zoriorz@gmail.com>

require 'yaml'
require 'rubygems'
require 'googlecalendar/calendar'
require 'date'
require 'mhc-schedule'
require 'mhc-kconv'
require 'nkf'

def usage(do_exit = true)
  STDERR .print "usage: #{$0} [options]
  Upload your MHC schedule to Google Calendar:
  --help               show this message.
  --category=CATEGORY  pick only in CATEGORY. 
                       '!' and space separated multiple values are allowed.
  --secret=CATEGORY    change the title of the event to 'SECRET'
                       space separated multiple values are allowed.
  --date={string[+n],string-string}
                       set a period of date.
                       string is one of these:
                         today, tomorrow, sun ... sat, yyyymmdd, yyyymm, yyyy
                       yyyymm lists all days in the month and yyyy lists all
                       days in the year.
                       list n+1 days of schedules if +n is given.
                       default value is 'today+0'
  --description        add description.
  --verbose            verbose mode.
  --proxy-addr=addr    set the address of http proxy.
  --proxy-port=port    set the port number of http proxy.
  --proxy-user=user    set the username of http proxy.
  --proxy-pass=pass    set the password of http proxy.
  --config-file=file   set the name of configuration file.
  --version            display the version of mhc2gcal and exit.\n"
  exit if do_exit
end

def version(do_exit = true)
  STDOUT .print "mhc2gcal version #{MHC2GCAL_VERSION}\n"
  exit if do_exit
end

def string_to_date(string, range)
  date_from = nil
  date_to   = nil

  case (string .downcase)
  when 'today'
    date_from = MhcDate .new

  when 'tomorrow'
    date_from = MhcDate .new .succ

  when /^(sun|mon|tue|wed|thu|fri|sat)/
    date_from = MhcDate .new .w_this(string .downcase)

  when /^\d{8}$/
    date_from = MhcDate .new(string)

  when /^\d{6}$/
    date_from = MhcDate .new(string + '01')
    if range
      date_to = date_from .succ(range .to_i)
    else
      date_to = MhcDate .new(string + format("%02d", date_from .m_days))
    end

  when /^\d{4}$/
    date_from = MhcDate .new(string + '0101')
    if range
      date_to = date_from .succ(range .to_i)
    else
      date_to = MhcDate .new(string + '1231')
    end
  else
    return nil
  end

  date_to   = date_from .succ((range || '0') .to_i) if !date_to
  return [date_from, date_to]
end

def string_to_date2(s1, s2)
  item = []
  [s1, s2] .each{|string|
    case (string .downcase)
    when 'today'
      item << MhcDate .new
    when 'tomorrow'
      item << MhcDate .new .succ
    when /^(sun|mon|tue|wed|thu|fri|sat)/
      item << MhcDate .new .w_this(string .downcase)
    when /^\d{8}$/
      item << MhcDate .new(string)
    when /^\d{6}$/
      item << MhcDate .new(string + '01')
    when /^\d{4}$/
      item << MhcDate .new(string + '0101')
    else
      item << nil
    end
  }
  return item
end

MHC2GCAL_VERSION = '0.4.0'
gcal_yaml = File.expand_path('gcal.yaml', File.dirname($0))
date_from   = date_to = MhcDate .new
category   = '!Holiday'
secret     = 'Private'
verbose     = false
description = false
proxy_mode  = false
proxy_auth  = false

while option = ARGV .shift
  case (option)
  when /^--category=(.+)/
    category = $1
  when /^--secret=(.+)/
    secret = $1
  when /^--date=([^-]+)\-(.+)/
    date_from, date_to = string_to_date2($1, $2) || usage()
  when /^--date=([^+]+)(\+(-?[\d]+))?/
    date_from, date_to = string_to_date($1, $3) || usage()
  when /^--description/
    description = true
  when /^--verbose/
    verbose = true
  when /^--proxy-addr=(.+)/
    proxy_addr = $1
  when /^--proxy-port=(.+)/
    proxy_port = $1
  when /^--proxy-user=(.+)/
    proxy_user = $1
  when /^--proxy-pass=(.+)/
    proxy_pass = $1
  when /^--config-file=(.+)/
    gcal_yaml = $1
  when /^--version/
    version()
  else
    usage()
  end
end

if proxy_addr && proxy_port
  proxy_mode = true
  if proxy_user && proxy_pass
    proxy_auth = true
  end
end

secrets = nil
if secret
  if secret =~ /!/
    secret = secret .delete('!')
  end
  secrets = secret .split .collect{|x| x .downcase}
end

load_error=false
File.open( gcal_yaml ) do |io|
  YAML.load_documents(io){|y|
    defined? y['gcal_feed'] ? GCAL_FEED=y['gcal_feed'] : load_error=true
    defined? y['gcal_mail'] ? GCAL_MAIL=y['gcal_mail'] : load_error=true
    defined? y['gcal_pass'] ? GCAL_PASS=y['gcal_pass'] : load_error=true
    defined? y['gcal_mode'] ? GCAL_MODE=y['gcal_mode'] : load_error=true
  }
end
if GCAL_MODE == 'delete'
  GCAL_DEL=true
elsif GCAL_MODE == 'keep'
  GCAL_DEL=false
else
  load_error = true
end
if load_error == true
  p "YAML loading error..."
  exit
end

if proxy_mode
  GoogleCalendar::Service.proxy_addr=proxy_addr
  GoogleCalendar::Service.proxy_port=proxy_port
  if proxy_auth
    GoogleCalendar::Service.proxy_user=proxy_user
    GoogleCalendar::Service.proxy_pass=proxy_pass
    STDOUT .print "Connect to Google Calendar through proxy(#{proxy_user}:#{proxy_pass}@#{proxy_addr}:#{proxy_port})\n"
  else
    STDOUT .print "Connect to Google Calendar through proxy(#{proxy_addr}:#{proxy_port})\n"
  end
else
  STDOUT .print "Connect to Google Calendar directly\n"
end
srv = GoogleCalendar::Service.new(GCAL_MAIL, GCAL_PASS)
cal = GoogleCalendar::Calendar.new(srv, GCAL_FEED)
STDOUT .print "Connect as #{GCAL_MAIL}\n"

# init arrays for EVENTs in Google Calendar and MHC
gcal_gevs=[]
mhc_gevs=[]

# collect EVENTs from Google Calendarin the period of date
STDOUT .print "Collect EVENTs from Google Calendar\n"
st = Time.mktime(date_from.y.to_i, date_from.m.to_i, date_from.d.to_i, 0, 0, 0)
en = Time.mktime(date_to.y.to_i, date_to.m.to_i, date_to.d.to_i, 23, 59, 59)
cal.events(:'start-min' => st,
           :'start-max' => en,
           :'max-results' => 100).each do |event|
  if event.allday != true or event.en != Time.mktime(date_from.y.to_i, date_from.m.to_i, date_from.d.to_i)
    gcal_gevs.push(event)
  end
end

# collect EVENTs from MHC in the period of date
STDOUT .print "Collect EVENTs from MHC\n"
db = MhcScheduleDB .new
db .search(date_from, date_to, category) .each{|date, mevs|
  mevs .each {|mev|
    gev = cal.create_event
    secret_event = false
    secrets.each{|secret_category|
      regexp = Regexp.new(secret_category, nil, "e")
      if regexp =~ mev.category_as_string.downcase
        secret_event = true
        break
      end
    }
    if secret_event == true
      gev.title = "SECRET"
    else
      gev.title = NKF.nkf("-w", mev.subject)
    end
    if mev.location and mev.location != ""
      gev.where =  NKF.nkf("-w", mev.location)
    else
      gev.where =  ""
    end
    if mev.time_b.to_s != ""
      gev.st = Time.parse(date.y.to_s + "/" + date.m.to_s + "/" + date.d.to_s + " " + mev.time_b.to_s)
      if mev.time_e.to_s != ""
        if mev.time_e.to_i < 86400
          gev.en = Time.parse(date.y.to_s + "/" + date.m.to_s + "/" + date.d.to_s + " " + mev.time_e.to_s)
        else
          gev.en = Time.parse(date.y.to_s + "/" + date.m.to_s + "/" + date.d.to_s + " 23:59")
        end
      else
        gev.en = Time.parse(date.y.to_s + "/" + date.m.to_s + "/" + date.d.to_s + " " + mev.time_b.to_s)
      end
    else
      allday_start = Date::new(date.y.to_i, date.m.to_i, date.d.to_i)
      allday_end = allday_start + 1
      gev.st = Time.parse(allday_start.to_s)
      gev.en = Time.parse(allday_end.to_s)
      gev.allday = true
    end
    if description == true
      headers = "Category: " + mev .category_as_string + "\n"
      switch = false
      mev .non_xsc_header .split("\n") .each{|line|
        if line =~ /^(subject|from|to|cc|x-ur[il]):/i
          headers += line + "\n"
          switch = true
        elsif switch && line =~ /^[ \t]/
          headers += line + "\n"
        else
          switch = false
        end
      }
      gev.desc = NKF.nkf("-w", headers + "\n" + mev .description .to_s)
    end
    mhc_gevs.push(gev)
    if verbose == true
    end
  }
}

gcal_gevs.uniq
mhc_gevs.uniq

# compare and delete EVENTs only in Google Calendar
gcal_gevs.each{|gcal_gev|
  find_the_same_event = false
  mhc_gevs.each{|mhc_gev|
    if mhc_gev.title == gcal_gev.title &&
        mhc_gev.where == gcal_gev.where &&
        mhc_gev.st == gcal_gev.st &&
        mhc_gev.en == gcal_gev.en &&
        mhc_gev.desc == gcal_gev.desc
      find_the_same_event = true
      break
    end
  }
  if find_the_same_event != true
    if GCAL_DEL
      gcal_gev.destroy!
    end
    if verbose == true
      if GCAL_DEL
        STDOUT .print "Delete EVENT only in Google Calendar\n"
      else
        STDOUT .print "Keep EVENT only in Google Calendar\n"
      end
      STDOUT .print "  What: #{gcal_gev.title}\n"
      STDOUT .print "  When: #{gcal_gev.st.to_s} - #{gcal_gev.en.to_s}\n"
      STDOUT .print "  Where: #{gcal_gev.where}\n"
    end
  end
}

# compare and create EVENTs only in MHC
mhc_gevs.each{|mhc_gev|
  find_the_same_event = false
  gcal_gevs.each{|gcal_gev|
    if mhc_gev.title == gcal_gev.title &&
        mhc_gev.where == gcal_gev.where &&
        mhc_gev.st == gcal_gev.st &&
        mhc_gev.en == gcal_gev.en &&
        mhc_gev.desc == gcal_gev.desc
      find_the_same_event = true
      break
    end
  }
  if find_the_same_event != true
    mhc_gev.save!
    if verbose == true
      STDOUT .print "Create EVENT only in MHC\n"
      STDOUT .print "  What: #{mhc_gev.title}\n"
      STDOUT .print "  When: #{mhc_gev.st.to_s} - #{mhc_gev.en.to_s}\n"
      STDOUT .print "  Where: #{mhc_gev.where}\n"
    end
  end
}

### Copyright Notice:

## Copyright (C) 2007 Nao Kawanishi <river2470@gmail.com>. All rights reserved.

## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions
## are met:
## 
## 1. Redistributions of source code must retain the above copyright
##    notice, this list of conditions and the following disclaimer.
## 2. Redistributions in binary form must reproduce the above copyright
##    notice, this list of conditions and the following disclaimer in the
##    documentation and/or other materials provided with the distribution.
## 3. Neither the name of the team nor the names of its contributors
##    may be used to endorse or promote products derived from this software
##    without specific prior written permission.
## 
## THIS SOFTWARE IS PROVIDED BY THE TEAM AND CONTRIBUTORS ``AS IS''
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
## LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
## FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
## THE TEAM OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
## INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
## (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
## SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
## HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
## STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
## OF THE POSSIBILITY OF SUCH DAMAGE.

### mhc2gcal ends here
