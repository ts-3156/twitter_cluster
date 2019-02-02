module TwitterCluster
  module List
    def hashtag_clusters(hashtags, limit: 10, debug: false)
      puts "hashtags: #{hashtags.take(10)}" if debug

      hashtag, count = hashtags.take(3).each_with_object(Hash.new(0)) do |tag, memo|
        tweets = search(tag)
        puts "tweets #{tag}: #{tweets.size}" if debug
        memo[tag] = count_freq_hashtags(tweets).reject { |t, c| t == tag }.values.sum
      end.max_by { |_, c| c }

      hashtags = count_freq_hashtags(search(hashtag)).reject { |t, c| t == hashtag }.keys
      queries = hashtags.take(3).combination(2).map { |ary| ary.join(' AND ') }
      puts "selected #{hashtag}: #{queries.inspect}" if debug

      tweets = queries.map { |q| search(q) }.flatten
      puts "tweets #{queries.inspect}: #{tweets.size}" if debug

      if tweets.empty?
        tweets = search(hashtag)
        puts "tweets #{hashtag}: #{tweets.size}" if debug
      end

      members = tweets.map { |t| t.user }
      puts "members count: #{members.size}" if debug

      count_freq_words(members.map { |m| m.description  }, special_words: PROFILE_SPECIAL_WORDS, exclude_words: PROFILE_EXCLUDE_WORDS, special_regexp: PROFILE_SPECIAL_REGEXP, exclude_regexp: PROFILE_EXCLUDE_REGEXP, debug: debug).take(limit)
    end
  end
end