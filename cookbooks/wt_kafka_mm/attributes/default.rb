#
# Author: Jeff Berger (<jeff.berger@webtrends.com>)
# Cookbook Name:: wt_kafka_mm
# Recipe:: default
#
# Copyright 2012, Webtrends
#

default['wt_kafka_mm']['user']         = "webtrends"
default['wt_kafka_mm']['group']        = "webtrends"
default['wt_kafka_mm']['java_opts']    = "-Xms1024m -Djava.net.preferIPv4Stack=true"
default['wt_kafka_mm']['jmx_port']    = "10000"

default['wt_kafka_mm']['topic_white_list'] = ".*RawHits"

default['wt_kafka_mm']['log_level'] = "INFO"

default['wt_kafka_mm']['sources'] = {}
default['wt_kafka_mm']['target'] = {}

#monitoring
node["wt_kafka_mm"]["averagecount"] = 100
node["wt_kafka_mm"]["ratethreshold"] = 8000
node["wt_kafka_mm"]["avgthreshold"] = 8000
node["wt_kafka_mm"]["producerate"] = 5000