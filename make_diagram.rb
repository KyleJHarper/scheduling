#!/usr/bin/ruby

#
# Function Definitions
#
def printActivity(job, attributes)
  # Print out a div that will display a pert-style activity.
  crit = "";
  crit = " act_critcal" if attributes["slack"] == 0
  puts "      <div id='#{job}' class='item' style='left: #{attributes['left'] * 200}px; top: #{attributes['top'] * 200}px;'>"
  puts "        <div class='act_banner'>#{job}</div>"
  puts "        <div class='act_row'>"
  puts "          <div class='activity act_narrow'>#{attributes['early_start']}</div>"
  puts "          <div class='activity act_wide act_id'>&nbsp;</div>"
  puts "          <div class='activity act_narrow'>#{attributes['late_start']}</div>"
  puts "        </div>"
  puts "        <div class='act_row'>"
  puts "          <div class='activity act_narrow #{crit}'>#{attributes['slack']}</div>"
  puts "          <div class='activity act_desc'>#{attributes['description']}</div>"
  puts "        </div>"
  puts "        <div class='act_row'>"
  puts "          <div class='activity act_narrow'>#{attributes['early_finish']}</div>"
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
@current = {}
left=0
top=0
longest_finish = 0
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
    lowest_top = 0
    attributes["dependencies"].each {|dependency| lowest_top = @schedule[dependency]["top"]  if @schedule[dependency].has_key?("top")}
    # -- Now try to assign the lowest top value, incrementing if spaces are already taken.
    while tops_used.include?(lowest_top) ; lowest_top = lowest_top + 1 ; end
    @schedule[job]["top"] = lowest_top
    tops_used.push(lowest_top)
    # -- Determine ES and EF.  We use the parents' EF values (if any) and take the highest of them for our ES value.
    early_start = 0
    attributes["dependencies"].each {|dep| early_start = @schedule[dep]["early_finish"]  if @schedule[dep].has_key?("early_finish") && early_start < @schedule[dep]["early_finish"] }
    @schedule[job]["early_start"] = early_start
    @schedule[job]["early_finish"] = early_start + attributes["duration"]
    # -- LS, LF, and Slack can be calculated for all endpoints, and should be.  Otherwise they're found in the loop below.
    next unless @schedule.select{|s_job,s_attributes| s_attributes["dependencies"].include?(job) }.keys.empty?
    @schedule[job]["late_finish"] = @schedule[job]["early_finish"]
    @schedule[job]["late_start"] = @schedule[job]["late_finish"] - attributes["duration"]
    @schedule[job]["slack"] = @schedule[job]["late_start"] - @schedule[job]["early_start"]
  }
end

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
# -- Start the body and insert the divs.
puts "  <body>"
puts '    <div id="diagramContainer">'
@schedule.each {|job,attributes| printActivity(job, attributes) }
puts "    </div>"
# -- Load a script to initialize jsPlumb now, then run the snapto's.
puts '    <script>'
puts '      jsPlumb.ready(function() {'
puts '        jsPlumb.setContainer("diagramContainer");'
puts '        jsPlumb.Defaults.Connector = [ "Flowchart", { stub: [10, 10], midpoint: 0.0001, cornerRadius: 1.5 } ];'
@schedule.each {|job,attributes|
  attributes["dependencies"].each {|dependency|
    color = 'lightblue'
    color = 'red' if attributes["slack"] == 0 && @schedule[dependency]["slack"] == 0
    puts "        snapto('#{dependency}', '#{job}', '#{color}')"
  }
}
puts '      });'
puts '    </script>'


# -- Close out the body and html page.
puts "  </body>"
puts "</html>"
