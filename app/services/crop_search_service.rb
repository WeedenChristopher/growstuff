#Name: Christopher Weeden
#Course: CSC 415
#Semester: Fall 2018
#Instructor: Dr Pulimood
#Project name: ExpandedSearch
#Description: Modifies origional growstuff
#	      search function to allow for
#	      secondary names and misspelled
#	      ones
#Last modified: 10/26/2018
require "MisspelledSearch.rb"
#-------------------------------------------------------
#
#Function: alt_name_search()
#
#Parameters:
# input string; the users search term
#
#Pre-condition; no main names have been matched, input is a non-empty string
#Post-condition; an array of Crop is returned containing secondary name matches
#--------------------------------------------------------
def alt_names_search(query)
  sci_matches     = Crop.approved.joins(:scientific_names).where('scientific_names.name ILIKE ?', "%#{query}%").to_a
  alt_matches     = Crop.approved.joins(:alternate_names).where('alternate_names.name ILIKE ?', "%#{query}%").to_a
  sci_exact_match = Crop.approved.joins(:scientific_names).where(scientific_names: {name: query}).first
  alt_exact_match = Crop.approved.joins(:alternate_names).where(alternate_names: {name: query}).first
  sci_matches.push(*alt_matches)
  if alt_exact_match||sci_exact_match
    sci_matches.delete(sci_exact_match)
    sci_matches.delete(alt_exact_match)
    sci_matches.unshift(sci_exact_match)
    sci_matches.unshift(alt_exact_match)
    sci_matches.compact
  end
  sci_matches
end

# method moved from other file to here to lower coupling
# this change can be very easily changed back should this
# be bad practice
#-------------------------------------------------------
#
#Function: minimum()
#
#Parameters:
# input int; number one to compare
# input int; number two to compare
# input int; number three to compare
#
#Pre-condition; the three inputs must be numbers
#Post-condition; the minimum of the three numbers will
#		 be returned
#--------------------------------------------------------
def minimum(a, b, c)
	min = a
	if b < min
		min = b
	end
	if c < min
		min = c
	end
	min
end

#-------------------------------------------------------
#
#Function: computeEditDistance()
#
#Parameters:
# input string; main name
# input string; query to be matched with
#
#Pre-condition; no main names have been matched, no 
#		secondary names have been matched, 
#		input is a non-empty string
#Post-condition; an integer of the best edit distance is
#                returned
#--------------------------------------------------------
def computeEditDistances(name, query)
	# alternate name searching for this part will
	# come later
	# computes levenstien distance between two strings
	# by using a matrix of insertions deletions or
	# substitutions
	#
	# an array is standard for this algorythim
	#
	# basic error handling for empty terms
	if name.empty? || query.empty?
		return 10000
	end
	distance_array = Array.new(name.length+1, Array.new(query.length+1))
	# initializing initial array values
	for i in 0..name.length
		distance_array[i][0]=i
	end
	for i in 0..query.length
		distance_array[0][i]=i
	end
	cost = 0
	# first row and column filled with default values need to shift other
	# computations one in both directions
	for i in 1..name.length
		for j in 1..query.length
			if(name[i-1]==query[j-1])
				cost=-10
			else
				cost=1
			end
			distance_array[i][j]=minimum(distance_array[i-1][j]+1, distance_array[i][j-1]+1, 
						     distance_array[i-1][j-1]+cost)
		end
	end
	distance_array[name.length][query.length]
end

#-------------------------------------------------------
#
#Function: misspelledNames()
#
#Parameters:
# input Crop; array of every crop object
# input string; query to check
#
#Pre-condition; Array sent is nonempty
#Post-condition; a weighted queue of size ten correctly
#		 ordered with respect to edit distances
#--------------------------------------------------------
def fillBestFitNames(crop_obj, query)
	best_fit_crops = Array.new(10)
	edit_dist = Array.new(10,10000)	
	crop_obj.each { |x|
		dist = computeEditDistances(x.name, query)
		puts "#{dist}"
		index = 0;
		puts"#{index}"
		# finds where the edit distance should be in an array
		while index <= 10
			if index != 10 && dist < edit_dist[index]
				# maintains a sorted array of length ten
				best_fit_crops.insert(index, x)
				edit_dist.insert(index, dist)
				# deletes element at end (should be most expensive
				# edit distance)
				best_fit_crops.delete_at(10)
				edit_dist.delete_at(10)
				index = 10
			end
			index += 1
		end
		# out index is always left at index 9 (end of the array)
		# so we need to check if it left the while loop for reaching 
		# index 9 or that it is a smaller distance than index 9
	}
	# make sure ruby returns correct object
	puts"here!!!!!!!!!!!!!!!!"
	puts"#{edit_dist}"
	puts"#{best_fit_crops}"
	best_fit_crops
end

class CropSearchService
  # Crop.search(string)
  def self.search(query)
    if ENV['GROWSTUFF_ELASTICSEARCH'] == "true"
      search_str = query.nil? ? "" : query.downcase
      response = Crop.__elasticsearch__.search(
        query: {
          bool: {
            filter: {
              term: { "approval_status" => "approved" }
            },
            must: {
              query_string: {
                query: "*#{search_str}*"
              }
            }
          }
        }
      )
      response.records.to_a
    # original code for main name search
    else
      # if we don't have elasticsearch, just do a basic SQL query.
      # also, make sure it's an actual array not an activerecord
      # collection, so it matches what we get from elasticsearch and we can
      # manipulate it in the same ways (eg. deleting elements without deleting
      # the whole record from the db)
      matches = Crop.approved.where("name ILIKE ?", "%#{query}%").to_a
      
      # we want to make sure that exact matches come first, even if not
      # using elasticsearch (eg. in development)
      exact_match = Crop.approved.find_by(name: query)
      puts "#{matches}"
      puts "#{exact_match}"
      if exact_match
        matches.delete(exact_match)
        matches.unshift(exact_match)
      end
      # start of my changes
      if matches.empty? # these computations become increasingly more expensive as they go on
			# so they are separated out to same computation time
	matches = alt_names_search(query).clone
        if matches.empty?
	  full_list = Crop.approved.to_a.clone
	  matches = fillBestFitNames(full_list, query)
	end
      end
      matches
    end
  end
end
