class HostsController < ApplicationController
  before_filter :require_login, :except => [ :query, :externalNodes, :lookup ]
  before_filter :require_ssl, :except => [ :query, :externalNodes, :lookup ]
  before_filter :find_hosts, :only => :query
  before_filter :ajax_methods, :only => [:environment_selected, :architecture_selected, :os_selected]
  helper :hosts

  def index
    @search = Host.search(params[:search])
    @hosts = @search.paginate :page => params[:page]
  end

  def show
    # filter graph time range
    @range = (params["range"].empty? ? 7 : params["range"].to_i)
    range = @range.days.ago

    @host = Host.find params[:id]
    graphs = @host.graph(range)

    # runtime graph
    data = { :labels => graphs[:runtime_labels], :values => graphs[:runtime] }
    options = { :title => "Runtime"}
    @runtime_graph = setgraph(GoogleVisualr::AnnotatedTimeLine.new, data, options)

    # resource graph
    data = { :labels => graphs[:resources_labels], :values => graphs[:resources] }
    options = { :title => "Resource", :width => 800, :height => 300, :legend => 'bottom'}
    @resource_graph = setgraph(GoogleVisualr::LineChart.new, data, options)

    # summary report text
    @report_summary = Report.summarise(range, @host)
  end

  def new
    @host = Host.new
    @host.host_parameters.build
  end

  def create
    @host = Host.new(params[:host])
    if @host.save
      flash[:foreman_notice] = "Successfully created host."
      redirect_to @host
    else
      render :action => 'new'
    end
  end

  def edit_action
    if session[:selected].nil?
      flash[:foreman_error] = 'No Hosts selected'
      redirect_to(hosts_path)
    else
      @hosts = Host.find(session[:selected].keys)
    end
  end

  def edit
    @host = Host.find(params[:id])
    @environment = @host.environment
    @architecture = @host.architecture
    @operatingsystem = @host.operatingsystem
  end

  def update
    @host = Host.find(params[:id])
    if @host.update_attributes(params[:host])
      flash[:foreman_notice] = "Successfully updated host."
      redirect_to @host
    else
      render :action => 'edit'
    end
  end

  def edit_multiple
    if session[:selected].nil?
      flash[:foreman_error] = 'No Hosts selected'
      redirect_to(hosts_path)
    else
      @hosts = Host.find(session[:selected].keys)
    end
  end

  def update_multiple
    if params[:reset] == "true"
      reset_session
      @search = Host.search(params[:search])
      @hosts = @search.all.paginate(:page => params[:page])
      flash[:foreman_notice] = 'Session cleared.'
      redirect_to(hosts_path) and return
    end
    @hosts_without_params ||= {}
    @hosts_to_edit = Host.find(session[:selected].keys)
    @hosts_to_edit.each do |host_to_edit|
      myparams = []
      host_to_edit.host_parameters.each do |hp|
        myparams << hp.name.to_str
        unless params[:name][hp.name].chomp.empty?
           hp.value = params[:name][hp.name]
           host_to_edit.save(perform_validation = false)
        end
      end
      params[:name].each do |pname,pvalue|
        if !myparams.include?(pname) && !pvalue.chomp.empty?
          @hosts_without_params[host_to_edit.name] ||= []
          @hosts_without_params[host_to_edit.name] << pname
        end
      end
    end
    if @hosts_without_params.length !=0
        reset_session
        render :text => "\#These hosts did not have the selected parameters and were not updated: <br></br>" + @hosts_without_params.to_yaml.gsub("\n","<br>")
    else
    reset_session
    flash[:foreman_notice] = 'Updated hosts!'
    redirect_to(hosts_path)
    end
  end

  def add_parameter
    if session[:selected].nil?
      flash[:foreman_error] = 'No Hosts selected'
      redirect_to(hosts_path)
    else
      @hosts = Host.find(session[:selected].keys)
    end
  end

  def select_hostgroup
    if session[:selected].nil?
      flash[:foreman_error] = 'No Hosts selected'
      redirect_to(hosts_path)
    else
      @hosts = Host.find(session[:selected].keys, :order => "hostgroup_id ASC")
    end
  end

  def update_hostgroup
    if params["hostgroup"]["hostgroup_id_equals"].empty?
      flash[:foreman_error] = 'No Hostgroup selected!'
      redirect_to(select_hostgroup_hosts_path) and return
    end
    @hosts_to_edit = Host.find(:all, :conditions => {:id => session[:selected].keys})
    @hosts_to_edit.each do |host_to_edit|
      hg = Hostgroup.find(params["hostgroup"]["hostgroup_id_equals"])
      !hg.nil? && host_to_edit.hostgroup=hg
      host_to_edit.save(perform_validation = false)
    end
    reset_session
    flash[:foreman_notice] = 'Updated hosts: Changed Hostgroup'
    redirect_to(hosts_path)
  end

  def destroy
    @host = Host.find(params[:id])
    if @host.destroy
      flash[:foreman_notice] = "Successfully destroyed host."
    else
      flash[:foreman_error] = @host.errors.full_messages.join("<br>")
    end
    redirect_to hosts_url
  end

  # form AJAX methods

  def environment_selected
    if params[:environment_id].to_i > 0 and @environment = Environment.find(params[:environment_id])
      render :partial => 'puppetclasses/class_selection', :locals => {:obj => (@host ||= Host.new)}
    else
      return head(:not_found)
    end
  end

  def architecture_selected
    assign_parameter "architecture"
  end

  def os_selected
    assign_parameter "operatingsystem"
  end

  def save_checkbox
    session[:selected] ||= {}
    params[:is_checked] == "true" && session[:selected][params[:box]] = params[:box]
    params[:is_checked] == "false" && session[:selected][params[:box]] = nil
    render :nothing => true
  end

 # list AJAX methods
  def fact_selected
    @fact_name_id = params[:search_fact_values_fact_name_id_eq].to_i
    @fact_values = FactValue.find(:all, :select => 'DISTINCT value', :conditions => {
      :fact_name_id => @fact_name_id }, :order => 'value ASC') if @fact_name_id > 0
    render :partial => 'fact_selected', :layout => false
  end

  #returns a yaml file ready to use for puppet external nodes script
  #expected a fqdn parameter to provide hostname to lookup
  #see example script in extras directory
  #will return HTML error codes upon failure

  def externalNodes
    # check our parameters and look for a host
    if params[:id] and @host = Host.find(params[:id])
    elsif params["name"] and @host = Host.find(:first,:conditions => ["name = ?",params["name"]])
    else
      render :text => '404 Not Found', :status => 404 and return
    end

    begin
      respond_to do |format|
        format.html { render :text => @host.info.to_yaml.gsub("\n","<br>") }
        format.yml { render :text => @host.info.to_yaml }
      end
    rescue
      # failed
      logger.warn "Failed to generate external nodes for #{@host.name} with #{$!}"
      render :text => 'Unable to generate output, Check log files', :status => 412 and return
    end
  end

  def puppetrun
    host = Host.find params[:id]
    if GW::Puppet.run host.name
      render :text => "Successfully executed, check log files for more details"
    else
      render :text => "Failed, check log files"
    end
  end

  def setBuild
    host = Host.find params[:id]
    if host.setBuild != false
      flash[:foreman_notice] = "Enabled #{host.name} for installation boot away"
    else
      flash[:foreman_error] = "Failed to enable #{host.name} for installation"
    end
    redirect_to :back
  end

  # generates a link to Puppetmaster RD graphs
  def rrdreport
    if SETTINGS[:rrd_report_url].nil? or (host=Host.find(params[:id])).last_report.nil?
      render :text => "Sorry, no graphs for this host"
    else
      render :partial => "rrdreport", :locals => { :host => host}
    end
  end

  # shows the last report for a host
  def report
    # is it safe to assume that the biggest ID is the last report?
    redirect_to :controller => "reports", :action => "show", :id => Report.maximum('id', :conditions => {:host_id => params[:id]})
  end

  # shows all reports for a certian host
  def reports
    @host = Host.find(params[:id])
  end

  def query
    respond_to do |format|
      format.html
      format.yml { render :text => @hosts.to_yaml }
    end
  end

  def facts
    @host = Host.find(params[:id])
  end

  def storeconfig_klasses
    @host = Host.find(params[:id])
  end

  private
  def find_hosts
    fact, klass = params[:fact], params[:class]
    if fact.empty? and klass.empty?
      render :text => '404 Not Found', :status => 404 and return
    end

    @hosts = []
    counter = 0

    case params[:state]
    when "out_of_sync"
      state = "out_of_sync"
    when "all"
      state = "all"
    when "active", nil
      state = "recent"
    else
      raise invalid_request and return
    end

    # TODO: rewrite this part, my brain stopped working
    # it should be possible for a one join
    fact.each do |f|
      # split facts based on name => value pairs
      q = f.split("-seperator-")
      invalid_request unless q.size == 2
      list = Host.with_fact(*q).send(state).map(&:name)
      @hosts = counter == 0 ? list : @hosts & list
      counter +=1
    end unless fact.nil?

    klass.each do |k|
      list = Host.with_class(k).send(state).map(&:name)
      @hosts = counter == 0 ? list : @hosts & list
      counter +=1
    end unless klass.nil?

    render :text => '404 Not Found', :status => 404 and return if @hosts.empty?
  end

  def ajax_methods
    return head(:method_not_allowed) unless request.xhr?
    @host = Host.find(params[:id]) unless params[:id].empty?
  end

  def assign_parameter name
    if params["#{name}_id"].to_i > 0 and eval("@#{name} = #{name.capitalize}.find(params['#{name}_id'])")
      render :partial => name, :locals => {:host => (@host ||= Host.new)}
    else
      return head(:not_found)
    end
  end
end
