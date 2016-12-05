#!/usr/bin/ruby

# Build a hash to emulate what we would get from Puppet.
@schedule = {
  "jobA" => {"duration" => 15,   "dependencies" => ["jobX"],         "description" => "yar matey"},
  "jobB" => {"duration" => 40,   "dependencies" => ["jobA"],         "description" => "this is another job"},
  "jobC" => {"duration" => 9999, "dependencies" => ["jobA"],         "description" => "this job containsareallylongwordthatdoesntbreasily but we'll use it anyway"},
  "jobD" => {"duration" => 30,   "dependencies" => ["jobB"],         "description" => "here we go loopty loooo"},
  "jobE" => {"duration" => 25,   "dependencies" => ["jobC"],         "description" => "I am another job on another path"},
  "jobF" => {"duration" => 115,  "dependencies" => ["jobD", "jobE"], "description" => "I am a merge event"},
  "jobG" => {"duration" => 95,   "dependencies" => ["jobD"],         "description" => "I continue on"},
  "jobH" => {"duration" => 45,   "dependencies" => ["jobG"],         "description" => "This becomes a seconardy end point"},
  "jobI" => {"duration" => 20,   "dependencies" => ["jobF", "jobH"], "description" => "This becomes another endpoint"},

  "jobX" => {"duration" => 15,   "dependencies" => [],               "description" => "The real initial job to ensure hash order doesn't matter"},
}
# Validate the schedule...
# -- Kill duplicates because users make me cry.
@duplicate_jobs = @schedule.keys.detect {|k| @schedule.keys.count(k) > 1}
abort("You cannot have duplicate jobs in a schedule: #{@duplicate_jobs}") if @duplicate_jobs
@schedule.map {|job, attributes| abort("You cannot make a job a dependency of itself...: #{job}") if attributes["dependencies"].include?(job)}
# -- While not fatal, squash any duplicate dependencies to avoid calling .uniq a million times.
@schedule.map {|job, attributes| attributes["dependencies"].uniq! }
# -- TODO There must be at least 1 job that has no dependencies... otherwise it's cyclical and/or incomplete.
# -- TODO All dependencies for all jobs must exist as pending jobs in the schedule... duh.


# Try to figure out where the paths lead so we can set top and left properties correctly.
@completed = []
@current = {}
left=0
LEFT_SPACING=200
top=0
TOP_SPACING=200
while ! (@schedule.keys - @completed).empty?
  # Find all of the jobs who's dependencies have already been processed.
  @current = @schedule.select { |job,attributes| (attributes["dependencies"] - @completed).empty? && !@completed.include?(job) }
  abort("There are more jobs to process, but we couldn't find any remaining starting points.  This usually means you have a cyclical dependency problem.") if @current.keys.empty?
  puts "\nFound the following to work with: #{@current.keys}"
  # Push the keys into the completed array so we don't process them again.
  @completed.push(@current.keys).flatten!
  # Assign the correct 'left' value for horizontal positioning later.
  @current.keys.each {|job| @schedule[job]["left"] = left }
  left = left + LEFT_SPACING
  # Calculate the appropriate 'top' value for vertical positioning later, for each job.
  tops_used = []
  @current.map {|job, attributes|
    # -- Get the predicate 'top' value(s).  Attempt to use the lowest of the parents; 0 if none.
    predicates = @schedule.select{|s_job,s_attributes| attributes["dependencies"].include?(s_job)}.keys
    lowest_top = 0
    predicates.each {|predicate| lowest_top = @schedule[predicate]["top"]  if @schedule[predicate].has_key?("top")}
    # -- Now try to assign the lowest top value, incrementing if spaces are already taken.
    while tops_used.include?(lowest_top) ; lowest_top = lowest_top + TOP_SPACING ; end
    @schedule[job]["top"] = lowest_top
    tops_used.push(lowest_top)
    puts "Job #{job} appears to have these predicates: #{predicates} with a lowest_top of: #{lowest_top}"
  }
end
