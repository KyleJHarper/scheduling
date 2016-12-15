#!/usr/bin/ruby

#
# Function Definitions
#
def printActivity(job, attributes)
  # Print out a div that will display a pert-style activity.
  crit = "";
  crit = " act_critcal" if attributes["slack"] == 0
  endpoint = "";
  endpoint = " act_endpoint" if @endpoints.include?(job)
  startpoint = "";
  startpoint = " act_startpoint" if attributes["dependencies"].empty?
  style = "left: #{attributes['left'] * 160}px; top: #{attributes['top'] * 160}px;"
  style = "position: relative" if job == 'Sample'
  legend_class = ""
  legend_class = " legend_symbol" if job == 'Sample'
  puts "      <div id='#{job}' class='item#{legend_class}' style='#{style}'>"
  puts "        <div class='act_banner#{endpoint}#{startpoint}'>#{job}</div>"
  puts "        <div class='act_row'>"
  puts "          <div class='activity act_narrow'>#{attributes['early_start']}</div>"
  puts "          <div class='activity act_wide act_id'>&nbsp;</div>"
  puts "          <div class='activity act_narrow'>#{attributes['early_finish']}</div>"
  puts "        </div>"
  puts "        <div class='act_row'>"
  puts "          <div class='activity act_narrow #{crit}'>#{attributes['slack']}</div>"
  puts "          <div class='activity act_desc'>#{attributes['description']}</div>"
  puts "        </div>"
  puts "        <div class='act_row'>"
  puts "          <div class='activity act_narrow'>#{attributes['late_start']}</div>"
  puts "          <div class='activity act_wide act_id'>#{attributes['duration']}</div>"
  puts "          <div class='activity act_narrow'>#{attributes['late_finish']}</div>"
  puts "        </div>"
  puts "      </div>"
end


# Load YAML and the data.
require 'yaml'
@data = YAML.load_file('data.yaml')
@schedule = @data["schedule"]

# Validate the schedule...
# 1. Kill duplicates because users make me cry.
@duplicate_jobs = @schedule.keys.detect {|k| @schedule.keys.count(k) > 1}
abort("You cannot have duplicate jobs in a schedule: #{@duplicate_jobs}") if @duplicate_jobs
# 2. Job cannot contain a dependency of itself.
@schedule.each {|job, attributes| abort("You cannot make a job a dependency of itself...: #{job}") if attributes["dependencies"].include?(job)}
# 3. While not fatal, squash any duplicate dependencies to avoid calling .uniq a million times.
@schedule.each {|job, attributes| attributes["dependencies"].uniq! }
# 4. There must be at least 1 job that has no dependencies... otherwise it's cyclical and/or incomplete.
abort("You must specify at least one root job (a job with no dependencies), otherwise the schedule is cyclical and/or incomplete.") if @schedule.select{|job, attributes| attributes["dependencies"].empty? }.empty?
# 5. All dependencies for all jobs must exist as pending jobs in the schedule... duh.  (If a dep exists for a job from another schedule, then those schedules are actually integral.)
@deps_not_in_schedule = @schedule.select{|job,attributes| !(attributes["dependencies"] - @schedule.keys).empty? }.keys
abort("The following jobs have dependencies that don't exist in the schedule, this shouldn't happen: #{@deps_not_in_schedule}") if !@deps_not_in_schedule.empty?
# 6. All jobs must have a duration and it must be greater than zero.
@invalid_durations = @schedule.select{|job,attributes| !attributes.has_key?("duration") || attributes["duration"] < 1 }.keys
abort("The following jobs are either missing a duration or have a duration of zero: #{@invalid_durations}") if !@invalid_durations.empty?

# Compute the top and left values for display purposes, then calculate the early start and early finish values.
@completed = []
@endpoints = []
@current = {}
left=0
top=0
biggest_early_finish = 0
while ! (@schedule.keys - @completed).empty?
  # Find all of the jobs who's dependencies have already been processed.
  @current = @schedule.select { |job,attributes| (attributes["dependencies"] - @completed).empty? && !@completed.include?(job) }
  abort("There are more jobs to process, but we couldn't find any remaining starting points.  This usually means you have a cyclical dependency problem.") if @current.keys.empty?
  # Push the keys into the completed array so we don't process them again.
  @completed.push(@current.keys).flatten!
  # Assign the correct 'left' value for horizontal positioning later.
  @current.keys.each {|job| @schedule[job]["left"] = left }
  left = left + 1
  # Calculate the appropriate 'top' value for vertical positioning later, for each job.
  tops_used = []
  @current.each {|job, attributes|
    # -- Get the 'top' value(s) of the dependencies.  Attempt to use the lowest of the parents; 0 if none.
    nearest_top = 0
    offset = 0
    attributes["dependencies"].each {|dependency| nearest_top = @schedule[dependency]["top"]  if @schedule[dependency].has_key?("top")}
    # -- Now try to assign the closest top value of the lowest_parent, shifting up and down as we're able.
    while true
      if !tops_used.include?(nearest_top + offset) ; nearest_top = nearest_top + offset ; break ; end
      if !tops_used.include?(nearest_top - offset) ; nearest_top = nearest_top - offset ; break ; end
      offset = offset + 1
    end
    @schedule[job]["top"] = nearest_top
    tops_used.push(nearest_top)
    # -- Determine ES and EF.  We use the parents' EF values (if any) and take the highest of them for our ES value.
    early_start = 0
    attributes["dependencies"].each {|dep| early_start = @schedule[dep]["early_finish"]  if @schedule[dep].has_key?("early_finish") && early_start < @schedule[dep]["early_finish"] }
    @schedule[job]["early_start"] = early_start
    @schedule[job]["early_finish"] = early_start + attributes["duration"]
    biggest_early_finish = @schedule[job]["early_finish"]  if biggest_early_finish < @schedule[job]["early_finish"]
    # -- Track the endpoints so we can assign the biggest early finish later to begin reverse traversing.
    @endpoints.push(job)  if @schedule.select{|s_job,s_attributes| s_attributes["dependencies"].include?(job) }.keys.empty?
  }
end
# We may have set negative top values for ease of reading.  Find the lowest top and shift everyone as needed.
lowest_top_of_all = @schedule.min_by{|job,attributes| attributes["top"] }[1]["top"]
@schedule.each {|job,attributes| attributes["top"] = attributes["top"] + lowest_top_of_all.abs}  if lowest_top_of_all < 0

# Fix endpoints before calculating all the other jobs' LS, LF, and slack.
@endpoints.each {|endpoint|
  @schedule[endpoint]["late_finish"] = biggest_early_finish
  @schedule[endpoint]["late_start"] = @schedule[endpoint]["late_finish"] - @schedule[endpoint]["duration"]
  @schedule[endpoint]["slack"] = @schedule[endpoint]["late_start"] - @schedule[endpoint]["early_start"]
}

# Now loop again in reverse to compute the late finish, early finish, and slack times.
@unfinished = @schedule.dup
while ! @unfinished.keys.empty?
  # Find all jobs that aren't a dependency for any remaining jobs in the completed array.
  @current = @unfinished.select{|job,attributes| @unfinished.select{|s_job,s_attributes| s_attributes["dependencies"].include?(job) }.keys.empty? }
  abort("Didn't find any jobs to work with to calculate late start and finish.  This shouldn't happen.") if @current.keys.empty?
  # Calculate the actual values for each currently available task, then remove it from the unfinished hash.
  @current.each {|job, attributes|
    if attributes.has_key?("late_finish")
      @unfinished.delete(job)
      next
    end
    soonest_late_start = 0
    @schedule.select{|s_job,s_attributes| s_attributes["dependencies"].include?(job)}.each {|s_job,s_attributes|
      soonest_late_start = s_attributes["late_start"] if soonest_late_start == 0 || soonest_late_start > s_attributes["late_start"]
    }
    @schedule[job]["late_finish"] = soonest_late_start
    @schedule[job]["late_start"] = @schedule[job]["late_finish"] - attributes["duration"]
    @schedule[job]["slack"] = @schedule[job]["late_start"] - @schedule[job]["early_start"]
    @unfinished.delete(job)
  }
end


# Now build the actual HTML file.
# -- Build the HTML, HEAD, and links to Scripts/CSS
puts "<html>"
puts "  <head>"
puts '    <script type="text/javascript" src="jsPlumb-2.2.6.js"></script>'
puts '    <script type="text/javascript" src="diagram.js"></script>'
puts '    <link rel="stylesheet" type="text/css" href="diagram.css" media="screen" />'
puts "  </head>"
# -- Start the body and insert the legend and the activities.
puts "  <body>"
puts '    <div id="legend">'
puts '      <div class="legend_row legend_title">Legend</div>'
puts '      <div class="legend_row">'
puts '        <div class="act_banner act_startpoint legend_symbol">Start Point</div>'
puts '        <div class="legend_description">Starting activities for the schedule.  These are the jobs that will execute first.</div>'
puts '      </div>'
puts '      <div class="legend_row">'
puts '        <div class="act_banner legend_symbol">Middle Activity</div>'
puts "        <div class='legend_description'>Regular activities that have dependencies and will execute as soon as they're met.</div>"
puts '      </div>'
puts '      <div class="legend_row">'
puts '        <div class="act_banner act_endpoint legend_symbol">End Point</div>'
puts "        <div class='legend_description'>Final activities for the schedule.  Nothing depends on them.  Schedule is done when they're all done.</div>"
puts '      </div>'
puts '      <div class="legend_row">'
puts '        <div class="legend_symbol">'
puts '          <svg class="legend_svg">'
puts '            <defs>'
puts '              <marker id="dark_arrowhead" markerWidth="6" markerHeight="4" refX="0" refY="2" orient="auto">'
puts '                <polygon points="0 0, 4 2, 0 4" fill="darkblue"/>'
puts '              </marker>'
puts '            </defs>'
puts '            <line x1="0" y1="10" x2="110" y2="10" style="stroke:darkblue;stroke-width:4" marker-end="url(#dark_arrowhead)"/>'
puts '          </svg>'
puts '        </div>'
puts "        <div class='legend_description'>Indicates the critical path(s) the schedule is taking.</div>"
puts '      </div>'
puts '      <div class="legend_row">'
puts '        <div class="legend_symbol">'
puts '          <svg class="legend_svg">'
puts '            <defs>'
puts '              <marker id="light_arrowhead" markerWidth="6" markerHeight="4" refX="0" refY="2" orient="auto">'
puts '                <polygon points="0 0, 4 2, 0 4" fill="lightblue"/>'
puts '              </marker>'
puts '            </defs>'
puts '            <line x1="0" y1="10" x2="110" y2="10" style="stroke:lightblue;stroke-width:4" marker-end="url(#light_arrowhead)"/>'
puts '          </svg>'
puts '        </div>'
puts "        <div class='legend_description'>A path between jobs that has slack time.</div>"
puts '      </div>'
puts '      <div class="legend_row">'
printActivity('Sample', {'early_start' => 'ES', 'late_start' => 'LS', 'slack' => 'Slack', 'early_finish' => 'EF', 'duration' => 'Duration', 'late_finish' => 'LF', 'dependencies' => ['junk'], 'top' => 0, 'left' => 0})
puts "        <div class='legend_description'>"
puts "          <span class='act_info'>ES (Early Start)</span> is the earliest the job can possibly start under ideal circumstances.<br />"
puts "          <span class='act_info'>EF (Early Finish)</span> is the earliest the job can possibly finish under ideal cirumstances.<br />"
puts "          <span class='act_info'>Slack</span> is the amount of time this job could be delayed, or run long, without delaying the whole schedule.<br />"
puts "          <span class='act_info'>LS (Late Start)</span> is the latest the job should ever start under worst-case circumstances.<br />"
puts "          <span class='act_info'>LF (Late Finish)</span> is the latest the job should ever complete under worst-case circumstances.<br />"
puts "          <span class='act_info'>Duration</span> is how much time the job should take, in whatever unit (mins, hours, etc)."
puts "        </div>"
puts '      </div>'
puts '    </div>'
puts '    <div id="diagramContainer">'
@schedule.each {|job,attributes| printActivity(job, attributes) }
puts "    </div>"
# -- Load a script to initialize jsPlumb now, then run the snapto's.
puts '    <script>'
puts '      jsPlumb.ready(function() {'
puts '        jsPlumb.setContainer("diagramContainer");'
puts '        jsPlumb.Defaults.Connector = [ "Flowchart", { midpoint: 0.0001, cornerRadius: 1.5 } ];'
@schedule.each {|job,attributes|
  attributes["dependencies"].each {|dependency|
    color = 'lightblue'
    color = 'darkblue' if attributes["slack"] == 0 && @schedule[dependency]["slack"] == 0
    puts "        snapto('#{dependency}', '#{job}', '#{color}')"
  }
  puts "        jsPlumb.draggable('#{job}');"
}
puts '      });'
puts '    </script>'


# -- Close out the body and html page.
puts "  </body>"
puts "</html>"
