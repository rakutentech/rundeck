#
# Cookbook Name:: rundeck
# Recipe::server_install
#
# Copyright 2012, Peter Crossley
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'rundeck::default'

if node['rundeck']['secret_file'].nil?
  rundeck_secure = data_bag_item(node['rundeck']['rundeck_databag'], node['rundeck']['rundeck_databag_secure'])
  rundeck_users = data_bag_item(node['rundeck']['rundeck_databag'], node['rundeck']['rundeck_databag_users'])
  rundeck_rdbms = data_bag_item(node['rundeck']['rundeck_databag'], node['rundeck']['rundeck_databag_rdbms']) if node['rundeck']['rdbms']['enable']
else
  rundeck_secret = Chef::EncryptedDataBagItem.load_secret(node['rundeck']['secret_file'])
  rundeck_secure = Chef::EncryptedDataBagItem.load(node['rundeck']['rundeck_databag'], node['rundeck']['rundeck_databag_secure'], rundeck_secret)
  rundeck_users = Chef::EncryptedDataBagItem.load(node['rundeck']['rundeck_databag'], node['rundeck']['rundeck_databag_users'], rundeck_secret)
  rundeck_rdbms = Chef::EncryptedDataBagItem.load(node['rundeck']['rundeck_databag'], node['rundeck']['rundeck_databag_rdbms'], rundeck_secret) if node['rundeck']['rdbms']['enable']
  rundeck_ldap_databag = Chef::EncryptedDataBagItem.load(node['rundeck']['rundeck_databag'], node['rundeck']['rundeck_databag_ldap'], rundeck_secret)
  rundeck_ldap_bind_dn = rundeck_ldap_databag['binddn']
  rundeck_ldap_bind_pwd = rundeck_ldap_databag['bindpwd']
end

rundeck_ldap = node['rundeck']['ldap']
if node['rundeck']['rundeck_databag_aclpolicies']
  aclpolicies = data_bag_item(node['rundeck']['rundeck_databag'], node['rundeck']['rundeck_databag_aclpolicies'])
end

case node['platform_family']
when 'rhel'
  yum_repository 'rundeck' do
    description 'Rundeck - Release'
    url 'http://dl.bintray.com/rundeck/rundeck-rpm'
    gpgkey 'http://rundeck.org/keys/BUILD-GPG-KEY-Rundeck.org.key'
    gpgcheck true
    action :add
  end

  rundeck_version = node['rundeck']['rpm']['version'].split('-')[1]

  yum_package 'rundeck' do
    version node['rundeck']['rpm']['version'].split('-')[1, 2].join('-')
    action :install
  end

  yum_package 'rundeck-config' do
    version node['rundeck']['rpm']['version'].split('-')[1, 2].join('-')
    allow_downgrade true
    action :install
  end
else
  remote_file "#{Chef::Config[:file_cache_path]}/#{node['rundeck']['deb']['package']}" do
    source node['rundeck']['url']
    owner node['rundeck']['user']
    group node['rundeck']['group']
    checksum node['rundeck']['checksum']
    mode '0644'
  end

  rundeck_version = node['rundeck']['deb']['package'].split('-')[1]

  package node['rundeck']['url'] do
    action :install
    source "#{Chef::Config[:file_cache_path]}/#{node['rundeck']['deb']['package']}"
    provider Chef::Provider::Package::Dpkg
    options node['rundeck']['deb']['options'] if node['rundeck']['deb']['options']
  end
end

service 'rundeck' do
  service_name 'rundeckd'
  provider Chef::Provider::Service::Upstart
  supports status: true, restart: true
  action :nothing
end

directory node['rundeck']['basedir'] do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  recursive true
end

directory node['rundeck']['exec_logdir'] do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  recursive true
end

directory "#{node['rundeck']['basedir']}/projects" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  recursive true
end

directory "#{node['rundeck']['basedir']}/.chef" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  recursive true
  mode '0700'
end

template "#{node['rundeck']['basedir']}/.chef/knife.rb" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  source 'knife.rb.erb'
  variables(
    user_home: node['rundeck']['basedir'],
    node_name: node['rundeck']['user'],
    chef_server_url: node['rundeck']['chef_url']
  )
  notifies (node['rundeck']['restart_on_config_change'] ? :restart : :nothing), 'service[rundeck]', :delayed
end

directory "#{node['rundeck']['basedir']}/.ssh" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  recursive true
  mode '0700'
end

file "#{node['rundeck']['basedir']}/.ssh/id_rsa" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  mode '0600'
  backup false
  content rundeck_secure['private_key']
  only_if { !rundeck_secure['private_key'].nil? }
  notifies (node['rundeck']['restart_on_config_change'] ? :restart : :nothing), 'service[rundeck]', :delayed
end

cookbook_file "#{node['rundeck']['basedir']}/libext/rundeck-winrm-plugin-1.3.3.jar" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  mode '0644'
  backup false
  source 'rundeck-winrm-plugin-1.3.3.jar'
  checksum 'dac57210e7a782d574621d5df27517bed4f58ebb54a40b9adab435333a5a5133'
  notifies (node['rundeck']['restart_on_config_change'] ? :restart : :nothing), 'service[rundeck]', :delayed
end

template "#{node['rundeck']['basedir']}/exp/webapp/WEB-INF/web.xml" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  variables(
    rundeck_version: rundeck_version
  )
  source 'web.xml.erb'
  notifies (node['rundeck']['restart_on_config_change'] ? :restart : :nothing), 'service[rundeck]', :delayed
end

template "#{node['rundeck']['configdir']}/jaas-activedirectory.conf" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  source 'jaas-activedirectory.conf.erb'
  variables(
    ldap: rundeck_ldap,
    binddn: rundeck_ldap_bind_dn || rundeck_ldap[:binddn],
    bindpwd: rundeck_ldap_bind_pwd || rundeck_ldap[:bindpwd],
    configdir: node['rundeck']['configdir']
  )
  notifies (node['rundeck']['restart_on_config_change'] ? :restart : :nothing), 'service[rundeck]', :delayed
end

template "#{node['rundeck']['configdir']}/profile" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  source 'profile.erb'
  variables(
    rundeck: node['rundeck']
  )
  notifies (node['rundeck']['restart_on_config_change'] ? :restart : :nothing), 'service[rundeck]', :delayed
end

template "#{node['rundeck']['configdir']}/rundeck-config.properties" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  source 'rundeck-config.properties.erb'
  variables(
    rundeck: node['rundeck'],
    rundeck_rdbms: node['rundeck']['rdbms']['enable'] ? rundeck_rdbms['rdbms'] : nil
  )
  notifies (node['rundeck']['restart_on_config_change'] ? :restart : :nothing), 'service[rundeck]', :delayed
end

if node.normal['rundeck']['server']['uuid'].empty?
  node.normal['rundeck']['server']['uuid'] = RundeckHelper.generateuuid
end

template "#{node['rundeck']['configdir']}/framework.properties" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  source 'framework.properties.erb'
  variables(
    rundeck: node['rundeck'],
    rundeck_users: rundeck_users['users'],
    rundeck_uuid: node.normal['rundeck']['server']['uuid']
  )
  notifies (node['rundeck']['restart_on_config_change'] ? :restart : :nothing), 'service[rundeck]', :delayed
end

template "#{node['rundeck']['configdir']}/realm.properties" do
  owner node['rundeck']['user']
  group node['rundeck']['group']
  source 'realm.properties.erb'
  variables(
    rundeck_users: rundeck_users['users']
  )
end

unless aclpolicies.nil?
  aclpolicies['aclpolicies'].each do |aclpolicy_name, aclpolicy|
    template "#{node['rundeck']['configdir']}/#{aclpolicy_name}.aclpolicy" do
      owner node['rundeck']['user']
      group node['rundeck']['group']
      source 'user.aclpolicy.erb'
      variables(
        aclpolicy: aclpolicy
      )
    end
  end
end

bash 'own rundeck' do
  user 'root'
  code <<-EOH
  chown -R #{node['rundeck']['user']}:#{node['rundeck']['group']} #{node['rundeck']['basedir']}
  EOH
end

service 'rundeckd' do
  action :start
end

bags = data_bag(node['rundeck']['rundeck_projects_databag'])

puts "chef-rundeck url: #{node['rundeck']['chef_rundeck_url']}"

# Assuming node['rundeck']['plugins'] is a hash containing name=>attributes
unless node['rundeck']['plugins'].nil?
  node['rundeck']['plugins'].each do |plugin_name, plugin_attrs|
    rundeck_plugin plugin_name do
      url plugin_attrs['url']
      checksum plugin_attrs['checksum']
      action :create
    end
  end
end

bags.each do |project|
  pdata = data_bag_item(node['rundeck']['rundeck_projects_databag'], project)
  custom = ''
  unless pdata['project_settings'].nil?
    pdata['project_settings'].map do |key, val|
      custom += " --#{key}=#{val}"
    end
  end

  cmd = <<-EOH.to_s
  rd projects -p #{project} create \
  --resources.source.1.type=url \
  --resources.source.1.config.includeServerNode=true \
  --resources.source.1.config.generateFileAutomatically=true \
  --resources.source.1.config.url=#{pdata['chef_rundeck_url'].nil? ? node['rundeck']['chef_rundeck_url'] : pdata['chef_rundeck_url']}/#{project} \
  --project.resources.file=#{node['rundeck']['datadir']}/projects/#{project}/etc/resources.xml #{custom}
  EOH

  bash "check-project-#{project}" do
    user node['rundeck']['user']
    code cmd.strip
    # will return 0 if grep matches
    # only run if project does not exist
    only_if "rd jobs -p #{project} list 2>&1 | grep -q '^ERROR .*project does not exist'"

    retries 5
    retry_delay 15
  end
end
