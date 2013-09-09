#!/usr/bin/env python
# A script to parse irssi log files and put URLs into postgresql
# supports two codecs, utf-8 and iso-8859-1.
# supports norwegian and us local for day changed messages
# author: xt  <xt@bash.no>
import codecs
import sys
import psycopg2
import re

verbose = False
maxlinelength = 2000
linenumber = 0
filenumber = 0
currentdate = u'0000-00-00'
startingid = 1


conn_string = "host='localhost' dbname='irc' user='' password='' "
conn = psycopg2.connect(conn_string)
cursor = conn.cursor()

octet = r'(?:2(?:[0-4]\d|5[0-5])|1\d\d|\d{1,2})'
ipAddr = r'%s(?:\.%s){3}' % (octet, octet)
# Base domain regex off RFC 1034 and 1738
label = r'[0-9a-z][-0-9a-z]*[0-9a-z]?'
domain = r'%s(?:\.%s)*\.[a-z][-0-9a-z]*[a-z]?' % (label, label)
urlRe = re.compile(r'(\w+://(?:%s|%s)(?::\d+)?(?:/[^\])>\s]*)?)' % (domain, ipAddr), re.I)

# dictionary of months for parse_date
months = {'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04', 'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08', 'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12', 'jan.': '01', 'feb.': '02', 'mars': '03', 'april':'04', 'mai':'05', 'juni':'06', 'juli':'07', 'aug.':'08', 'sep.':'09', 'okt.':'10', 'nov.':'11', 'dec.':'12'}

def store(date, time, nick, url, message):
    statement = 'insert into urls(time,nick,channel,url,message) values(%s,%s,%s,%s,%s)'
    cursor.execute(statement, ('%s %s' %(date, time), nick, channelname, url, message))
    conn.commit()

def handle(date, time, nick, message):
    for url in urlRe.findall(message):
        print 'URL:', date, time, nick, url, message
        store(date, time, nick, url, message)

# this function parses the date
def parse_date(irssidate):
	if len(irssidate) == 24:
		month = months[irssidate.split(' ')[1]]
		day = irssidate.split(' ')[2]
		year = irssidate.split(' ')[4]
	elif len(irssidate) == 15:
		month = months[irssidate.split(' ')[1]]
		day = irssidate.split(' ')[2]
		year = irssidate.split(' ')[3]
	return year + '-' + month + '-' + day

def get_nick(line):
    nick = line[line.find('<')+1:line.find('>')].lstrip('%@~+')
    return nick

def get_time(line):
    return line[0:5]

def get_message(line):
    return line[(len(line.split('>')[0])+2):-1]

def parse(file):
    global linenumber
    #f=codecs.open(file, mode='r', encoding='utf-8', errors='ignore') # <--- !!!
    f=open(file, mode='r') 
    filelinenumber = 0
    for line in f:
        # process each line of log
        try:
            line = line.decode('UTF-8')
        except UnicodeDecodeError :
            line = line.decode('iso-8859-1')
        except Exception:
            if verbose:
                print 'An error occured during line parsing', line
            pass
        linenumber = linenumber + 1
        filelinenumber = filelinenumber + 1
        #print 'line: ' + str(filelinenumber)
        startingline = 0
        if len(line) < 1:
            print 'Line too short.', line
        elif len(line) > maxlinelength:
            print 'Line too long.', line
        else:
            if line.find('--- Log opened') == 0:
            # this is when a log file is opened, day might change
                # set new current date
                try:
                    currentdate = parse_date(line[15:-1])
                    if verbose:
                        print 'Log opened!'
                except Exception:
                    print 'Failed to parse date', line
            elif line.find('--- Day changed') == 0:
            # this is when the day changes in the current log file, day should change
                # set new current date
                try:
                    currentdate = parse_date(line[16:-1])
                    if verbose:
                        print 'Day changed!', currentdate
                except Exception:
                    print 'Failed to parse date', line
                
            elif line.find('-!-') == 6:
                if line.find('Irssi: ' + channelname) != -1:
                # logging client joins channel
                    if verbose:
                        print 'The channel was joined!'
                elif line.find('has joined ' + channelname) != -1:
                # someone joins the channel
                    # get userid
                    if verbose:
                        print 'At ' + line[0:5] + ', ' + line.split(' ')[2] + ' joined ' + channelname
                elif line.find('has left ' + channelname) != -1:
                # someone parts the channel
                    if verbose:
                        print 'At ' + line[0:5] + ', ' + line.split(' ')[2] + ' left ' + channelname
                elif line.count(' ') >= 5 and line.split(' ')[5] == 'quit':
                # someone quits
                    if verbose:
                        print 'At ' + line[0:5] + ', ' + line.split(' ')[2] + ' quit.'
                elif line.count(' ') >= 2 and line.split(' ')[2] == 'mode/' + channelname:
                    if verbose:
                        print 'At ' + line[0:5] + ', a mode change happened!'
                elif line.find('is now known as') != -1:
                    if verbose:
                        print 'At ' + line[0:5] + ', ' + line.split(' ')[2] + ' changed his or her nick to '\
                        + line.split(' ')[7][0:-1]
                elif line.find('was kicked from ' + channelname) != -1:
                # a kick happens
                    if verbose:
                        print 'At ' + line[0:5] + ', ' + line.split(' ')[2] + ' was kicked from '\
                        + channelname + ' by ' + line.split(' ')[8] + ' for reason: '\
                        + line[(len(line.split(' ')[2]) + len(line.split(' ')[8]) + 37):-2]
                elif line.find('changed the topic of ' + channelname) != -1:
                # a topic change
                    if verbose:
                        print 'At ' + line[0:5] + ', ' + line.split(' ')[2] + 'changed the topic to '\
                        + line[(len(line.split(' ')[2]) + (len(channelname)) + 37):-1]
                else:
                    if verbose:
                        print 'An unrecognised line! ' + line
            elif line.count(' ') >= 2 and line.split(' ')[2] == '*':
            # an action
                # get userid
                if verbose:
                    print 'An action!'
            elif len(line) >= 7 and line[6] == '<':
                # a line of chat
                nick = get_nick(line)
                message = get_message(line)
                time = get_time(line)
                handle(currentdate, time, nick, message)
                if verbose:
                    print 'A line of chat!', nick, message


if __name__ == '__main__':
    channelname = sys.argv[1]
    parse(sys.argv[2])
