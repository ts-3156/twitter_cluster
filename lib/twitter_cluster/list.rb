module TwitterCluster
  module List
    def list_clusters(lists, shrink: false, shrink_limit: 100, list_member: 300, total_member: 3000, total_list: 50, rate: 0.3, limit: 10, debug: false)
      lists = lists.sort_by { |li| li.member_count }
      puts "lists: #{lists.size} (#{lists.map { |li| li.member_count }.join(', ')})" if debug
      return {} if lists.empty?

      open('lists.txt', 'w') {|f| f.write lists.map(&:full_name).join("\n") } if debug

      list_special_words = %w()
      list_exclude_regexp = %r(list[0-9]*|people-ive-faved|twizard-magic-list|my-favstar-fm-list|timeline-list|conversationlist|who-i-met)
      list_exclude_words = %w(it list people who met)

      # リスト名を - で分割 -> 1文字の単語を除去 -> 出現頻度の降順でソート
      words = lists.map { |li| li.full_name.split('/')[1] }.
          select { |n| !n.match(list_exclude_regexp) }.
          map { |n| n.split('-') }.flatten.
          delete_if { |w| w.size < 2 || list_exclude_words.include?(w) }.
          map { |w| SYNONYM_WORDS.has_key?(w) ? SYNONYM_WORDS[w] : w }.
          each_with_object(Hash.new(0)) { |w, memo| memo[w] += 1 }.
          sort_by { |k, v| [-v, -k.size] }

      puts "words: #{words.take(10)}" if debug
      return {} if words.empty?

      # 出現頻度の高い単語を名前に含むリストを抽出
      _words = []
      lists =
          filter(lists, min: 2) do |li, i|
            _words = words[0..i].map(&:first)
            name = li.full_name.split('/')[1]
            _words.any? { |w| name.include?(w) }
          end
      puts "lists include #{_words.inspect}: #{lists.size} (#{lists.map { |li| li.member_count }.join(', ')})" if debug
      return {} if lists.empty?

      # 中間の 25-75% のリストを抽出
      while lists.size > shrink_limit
        percentile25 = ((lists.length * 0.25).ceil) - 1
        percentile75 = ((lists.length * 0.75).ceil) - 1
        lists = lists[percentile25..percentile75]
        puts "lists sliced by 25-75 percentile: #{lists.size} (#{lists.map { |li| li.member_count }.join(', ')})" if debug
      end if shrink || lists.size > shrink_limit

      # メンバー数がしきい値より少ないリストを抽出
      _list_member = 0
      _min_list_member = 10 < lists.size ? 10 : 0
      _lists =
          filter(lists, min: 2) do |li, i|
            _list_member = list_member * (1.0 + 0.25 * i)
            _min_list_member < li.member_count && li.member_count < _list_member
          end
      lists = _lists.empty? ? [lists[0]] : _lists
      puts "lists limited by list member #{_min_list_member}..#{_list_member.round}: #{lists.size} (#{lists.map { |li| li.member_count }.join(', ')})" if debug
      return {} if lists.empty?

      # トータルメンバー数がしきい値より少なくなるリストを抽出
      _lists = []
      lists.size.times do |i|
        _lists = lists[0..(-1 - i)]
        if _lists.map { |li| li.member_count }.sum < total_member
          break
        else
          _lists = []
        end
      end
      lists = _lists.empty? ? [lists[0]] : _lists
      puts "lists limited by total members #{total_member}: #{lists.size} (#{lists.map { |li| li.member_count }.join(', ')})" if debug
      return {} if lists.empty?

      # リスト数がしきい値より少なくなるリストを抽出
      if lists.size > total_list
        lists = lists[0..(total_list - 1)]
      end
      puts "lists limited by total lists #{total_list}: #{lists.size} (#{lists.map { |li| li.member_count }.join(', ')})" if debug
      return {} if lists.empty?

      members = lists.map do |li|
        begin
          list_members(li.id)
        rescue Twitter::Error::NotFound => e
          puts "#{__method__}: #{e.class} #{e.message} #{li.id} #{li.full_name} #{li.mode}" if debug
          nil
        end
      end.compact.flatten
      puts "candidate members: #{members.size}" if debug
      return {} if members.empty?

      open('members.txt', 'w') {|f| f.write members.map{ |m| m.description.gsub(/\R/, ' ') }.join("\n") } if debug

      3.times do
        _members = members.each_with_object(Hash.new(0)) { |member, memo| memo[member] += 1 }.
            select { |_, v| lists.size * rate < v }.keys
        if _members.size > 100
          members = _members
          break
        else
          rate -= 0.05
        end
      end
      puts "members included multi lists #{rate.round(3)}: #{members.size}" if debug

      count_freq_words(members.map { |m| m.description }, special_words: PROFILE_SPECIAL_WORDS, exclude_words: PROFILE_EXCLUDE_WORDS, special_regexp: PROFILE_SPECIAL_REGEXP, exclude_regexp: PROFILE_EXCLUDE_REGEXP, debug: debug).take(limit)
    end
  end
end