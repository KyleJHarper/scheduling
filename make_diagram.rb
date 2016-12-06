#!/usr/bin/ruby

# Build a hash to emulate what we would get from Puppet.
@schedule = {
  "jobA" => {"duration" => 15,   "dependencies" => ["jobX"],         "description" => "yar matey"},
  "jobB" => {"duration" => 40,   "dependencies" => ["jobA"],         "description" => "this is another job"},
  "jobC" => {"duration" => 9000, "dependencies" => ["jobA"],         "description" => "this job containsareallylongwordthatdoesntbreasily but we'll use it anyway"},
  "jobD" => {"duration" => 30,   "dependencies" => ["jobB"],         "description" => "here we go loopty loooo"},
  "jobE" => {"duration" => 25,   "dependencies" => ["jobC"],         "description" => "I am another job on another path"},
  "jobF" => {"duration" => 115,  "dependencies" => ["jobD", "jobE"], "description" => "I am a merge event"},
  "jobG" => {"duration" => 95,   "dependencies" => ["jobD"],         "description" => "I continue on"},
  "jobH" => {"duration" => 45,   "dependencies" => ["jobG"],         "description" => "This becomes a seconardy end point"},
  "jobI" => {"duration" => 20,   "dependencies" => ["jobF", "jobH"], "description" => "This becomes another endpoint"},

  # Debugging jobs. They trigger failures (on purpose).
  # "jobP" => {"duration" => 15,   "dependencies" => [],               "description" => ""},   # 1. Duplicate job name
  # "jobQ" => {"duration" => 15,   "dependencies" => ["jobQ"],         "description" => ""},   # 2. Dependency of self
  # "jobR" => {"duration" => 15,   "dependencies" => ["nope"],         "description" => ""},   # 5. Dependencies must exist in schedule.
  # "jobS" => {                    "dependencies" => [],               "description" => ""},   # 6. Duration key must exist.
  # "jobT" => {"duration" => 0,    "dependencies" => [],               "description" => ""},   # 6. Duration must be greater than 0.

  "jobX" => {"duration" => 15,   "dependencies" => [],               "description" => "The real initial job to ensure hash order doesn't matter"},
}
# Validate the schedule...
# 1. Kill duplicates because users make me cry.
@duplicate_jobs = @schedule.keys.detect {|k| @schedule.keys.count(k) > 1}
abort("You cannot have duplicate jobs in a schedule: #{@duplicate_jobs}") if @duplicate_jobs
# 2. Job cannot contain a dependency of itself.
@schedule.map {|job, attributes| abort("You cannot make a job a dependency of itself...: #{job}") if attributes["dependencies"].include?(job)}
# 3. While not fatal, squash any duplicate dependencies to avoid calling .uniq a million times.
@schedule.map {|job, attributes| attributes["dependencies"].uniq! }
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
  @current.map {|job, attributes|
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
    longest_finish = early_start + attributes["duration"]  if longest_finish < early_start + attributes["duration"]
    # -- LS, LF, and Slack require all ES/EF to be finished.  So we do that in a loop below.
  }
end

# Now loop again in reverse to compute the late finish, early finish, and slack times.
@unfinished = @schedule.dup
while ! @unfinished.keys.empty?
  # Find all jobs that aren't a dependency for any remaining jobs in the completed array.
  @current = @unfinished.select{|job,attributes| @unfinished.select{|s_job,s_attributes| s_attributes["dependencies"].include?(job) }.keys.empty? }
  abort("Didn't find any jobs to work with to calculate late start and finish.  This shouldn't happen.") if @current.keys.empty?
  #puts "Working with #{@current.keys} now.\n"
  # Calculate the actual values for each currently available task, then remove it from the unfinished hash.
  next_longest_finish = longest_finish
  @current.map {|job, attributes|
    @schedule[job]["late_finish"] = longest_finish
    @schedule[job]["late_start"] = longest_finish - attributes["duration"]
    @schedule[job]["slack"] = @schedule[job]["late_start"] - @schedule[job]["early_start"]
    next_longest_finish = @schedule[job]["late_start"]  if @schedule[job]["late_start"] < next_longest_finish
    @unfinished.delete(job)
  }
  longest_finish = next_longest_finish
end

@schedule.map {|job, attributes|
  puts "Job #{job}"
  puts "  dependencies: #{@schedule[job]['dependencies']}"
  puts "  Top/Left    : #{@schedule[job]['top']}/#{@schedule[job]['left']}"
  puts "  ES/Dur/EF   : #{@schedule[job]['early_start']}  #{@schedule[job]['duration']}  #{@schedule[job]['early_finish']}"
  puts "  Slack       : #{@schedule[job]['slack']}"
  puts "  EF/Dur/LF   : #{@schedule[job]['early_finish']}  #{@schedule[job]['duration']}  #{@schedule[job]['late_finish']}"
}

# Now build the actual HTML file.
LEFT_SPACING=200
TOP_SPACING=200
