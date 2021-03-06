require 'test_helper'

class HostMailerTest < ActionMailer::TestCase
  def setup
    @env = Environment.new :name => "testing"
    @env.save!

    @host = Host.new :name => "myfullhost", :mac => "aabbecddeeff", :ip => "123.05.02.03",
      :domain => Domain.find_or_create_by_name("company.com"), :operatingsystem => Operatingsystem.first,
      :architecture => Architecture.first, :environment => @env, :disk => "empty partition",
      :ptable => Ptable.first, :last_report => nil
    @host.save!

    @env.hosts << @host
    @env.save!

    SETTINGS[:foreman_url] = "http://localhost:3000/hosts/:id"

    @options = {}
    @options[:env] = @env
  end

  test "mail should have the specified recipient" do
    @options[:email] = "ltolchinsky@vurbiatechnologies.com"
    assert HostMailer.deliver_summary(@options).to.include?("ltolchinsky@vurbiatechnologies.com")
  end

  test "mail should have admin as recipient if email is not defined" do
    @options[:email] = nil
    SETTINGS[:administrator] = "admin@vurbia.com"
    assert HostMailer.deliver_summary(@options).to.include?("admin@vurbia.com")
  end

  test "mail should have any recipient if email or admin are not defined" do
    user = User.new :mail => "chuck.norris@vurbia.com", :login => "Chuck_Norris"
    assert user.save!
    @options[:email] = nil
    SETTINGS[:administrator] = nil
    assert HostMailer.deliver_summary(@options).to.include?("chuck.norris@vurbia.com")
  end

  test "mail should have a subject" do
    assert !HostMailer.deliver_summary(@options).subject.empty?
  end

  test "mail should have a body" do
    assert !HostMailer.deliver_summary(@options).body.empty?
  end

  # TODO: add an assertion checking the presence of a fact filter.
  test "mail should contain a filter if it's defined" do
    @options[:env] = @env
    assert HostMailer.deliver_summary(@options).body.include?(@env.name)
  end

  # TODO: check presence of @host when a fact filter is passed.
  test "mail should have the host for the specific filter" do
    @options[:env] = @env
    assert HostMailer.deliver_summary(@options).body.include?(@host.name)
  end

  test "mail should report at least one host" do
    assert HostMailer.deliver_summary(@options).body.include?(@host.name)
  end
end
