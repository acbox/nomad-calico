Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-16.04"
  config.vm.provision "shell",
    inline: "wget https://apt.puppet.com/puppet7-release-xenial.deb && sudo dpkg -i puppet7-release-xenial.deb && apt update && apt install -y puppet-agent make gcc && /opt/puppetlabs/puppet/bin/gem install pry-byebug"
  config.vm.provision "puppet" do |puppet|
    puppet.module_path = "modules"
  end
end
