module TwitterCluster
  module Tweet
    PROFILE_SPECIAL_WORDS = %w(20↑ 成人済 腐女子)
    PROFILE_SPECIAL_REGEXP = nil
    PROFILE_EXCLUDE_WORDS = %w(in at of my to no er by is RT DM the and for you inc Inc com from info next gmail 好き こと 最近 紹介 連載 発売 依頼 情報 さん ちゃん くん 発言 関係 もの 活動 見解 所属 組織 代表 連絡 大好き サイト ブログ つぶやき 株式会社 最新 こちら 届け お仕事 ツイ 返信 プロ 今年 リプ ヘッダー アイコン アカ アカウント ツイート たま ブロック 無言 時間 お願い お願いします お願いいたします イベント フォロー フォロワー フォロバ スタッフ 自動 手動 迷言 名言 非公式 リリース 問い合わせ ツイッター)
    PROFILE_EXCLUDE_REGEXP = Regexp.union(/\w+@\w+\.(com|co\.jp)/, %r[\d{2,4}(年|/)\d{1,2}(月|/)\d{1,2}日], %r[\d{1,2}/\d{1,2}], /\d{2}th/, URI.regexp)

    def tweet_clusters(tweets, limit: 10, debug: false)
      return {} if tweets.blank?
      text = tweets.map(&:text).join(' ')

      if defined?(Rails)
        exclude_words = JSON.parse(File.read(Rails.configuration.x.constants['cluster_bad_words_path']))
        special_words = JSON.parse(File.read(Rails.configuration.x.constants['cluster_good_words_path']))
      else
        exclude_words = JSON.parse(File.read('./cluster_bad_words.json'))
        special_words = JSON.parse(File.read('./cluster_good_words.json'))
      end

      %w(べたら むっちゃ それとも たしかに さそう そんなに ったことある してるの しそうな おやくま ってますか これをやってるよ のせいか 面白い 可愛い).each { |w| exclude_words << w }
      %w(面白い 可愛い 食べ物 宇多田ヒカル ご飯 面倒 体調悪くなる 空腹 頑張ってない 眼鏡 台風 沖縄 らんま1/2 女の子 怪我 足のむくみ 彼女欲しい 彼氏欲しい 吐き気 注射 海鮮チヂミ 出勤 価格ドットコム 幹事 雑談 パズドラ ビオフェルミン 餃子 お金 まんだらけ 結婚 焼肉 タッチペン).each { |w| special_words << w }

      # クラスタ用の単語の出現回数を記録
      frequency =
          special_words.map { |sw| [sw, text.scan(sw)] }
              .delete_if { |_, matched| matched.empty? }
              .each_with_object(Hash.new(0)) { |(word, matched), memo| memo[word] = matched.size }

      # 同一文字種の繰り返しを見付ける。漢字の繰り返し、ひらがなの繰り返し、カタカナの繰り返し、など
      text.scan(/[一-龠〆ヵヶ々]+|[ぁ-んー～]+|[ァ-ヴー～]+|[ａ-ｚA-ZＡ-Ｚ０-９]+|[、。！!？?]+/).

          # 複数回繰り返される文字を除去
          map { |w| w.remove /[？！?!。、ｗ]|(ー{2,})/ }.

          # 文字数の少なすぎる単語、除外単語を除去する
          delete_if { |w| w.length <= 2 || exclude_words.include?(w) }.

          # 出現回数を記録
          each { |w| frequency[w] += 1 }

      # 複数個以上見付かった単語のみを残し、出現頻度順にソート
      frequency.select { |_, v| 2 < v }.sort_by { |k, v| [-v, -k.size] }.take(limit).to_h
    end

    def count_freq_hashtags(tweets, with_prefix: true, use_regexp: false, debug: false)
      puts "tweets: #{tweets.size}" if debug
      return {} if tweets.blank?

      prefix = %w(# ＃)
      regexp = /[#＃]([Ａ-Ｚａ-ｚA-Za-z_一-鿆0-9０-９ぁ-ヶｦ-ﾟー]+)/

      tweets =
          if use_regexp
            tweets.select { |t| t.text && prefix.any? { |char| t.text.include?(char)} }
          else
            tweets.select { |t| include_hashtags?(t) }
          end
      puts "tweets with hashtag: #{tweets.size}" if debug

      hashtags =
          if use_regexp
            tweets.map { |t| t.text.scan(regexp).flatten.map(&:strip) }
          else
            tweets.map { |t| extract_hashtags(t) }
          end.flatten
      hashtags = hashtags.map { |h| "#{prefix[0]}#{h}" } if with_prefix

      hashtags.each_with_object(Hash.new(0)) { |h, memo| memo[h] += 1 }.sort_by { |k, v| [-v, -k.size] }.to_h
    end

    def fetch_lists(user, debug: false)
      memberships(user, count: 500, call_limit: 2).sort_by { |li| li.member_count }
    rescue Twitter::Error::ServiceUnavailable => e
      puts "#{__method__}: #{e.class} #{e.message} #{user.inspect}" if debug
      []
    end

    private

    def filter(lists, min:)
      min = [min, lists.size].min
      _lists = []
      3.times do |i|
        _lists = lists.select { |li| yield(li, i) }
        break if _lists.size >= min
      end
      _lists
    end

    def count_by_word(texts, delim: nil, tagger: nil, min_length: 2, max_length: 5, special_words: [], exclude_words: [], special_regexp: nil, exclude_regexp: nil)
      texts = texts.dup

      frequency = Hash.new(0)
      if special_words.any?
        texts.each do |text|
          special_words.map { |sw| [sw, text.scan(sw)] }
              .delete_if { |_, matched| matched.empty? }
              .each_with_object(frequency) { |(word, matched), memo| memo[word] += matched.size }

        end
      end

      if exclude_regexp
        texts = texts.map { |t| t.remove(exclude_regexp) }
      end

      if delim
        texts = texts.map { |t| t.split(delim) }.flatten.map(&:strip)
      end

      if tagger
        texts = texts.map { |t| tagger.parse(t).split("\n") }.flatten.
            select { |line| line.include?('名詞') }.
            map { |line| line.split("\t")[0] }
      end

      texts.delete_if { |w| w.empty? || w.size < min_length || max_length < w.size || exclude_words.include?(w) || w.match(/\d{2}/) }.
          each_with_object(frequency) { |word, memo| memo[word] += 1 }.
          sort_by { |k, v| [-v, -k.size] }.to_h
    end

    def count_freq_words(texts, special_words: [], exclude_words: [], special_regexp: nil, exclude_regexp: nil, debug: false)
      candidates, remains = texts.partition { |desc| desc.scan('/').size > 2 }
      slash_freq = count_by_word(candidates, delim: '/', exclude_regexp: exclude_regexp)
      puts "words splitted by /: #{slash_freq.take(10)}" if debug

      candidates, remains = remains.partition { |desc| desc.scan('|').size > 2 }
      pipe_freq = count_by_word(candidates, delim: '|', exclude_regexp: exclude_regexp)
      puts "words splitted by |: #{pipe_freq.take(10)}" if debug

      noun_freq = count_by_word(remains, tagger: build_tagger, special_words: special_words, exclude_words: exclude_words, special_regexp: special_regexp, exclude_regexp: exclude_regexp)
      puts "words tagged as noun: #{noun_freq.take(10)}" if debug

      slash_freq.merge(pipe_freq) { |_, old, neww| old + neww }.
          merge(noun_freq) { |_, old, neww| old + neww }.sort_by { |k, v| [-v, -k.size] }
    end

    def build_tagger
      require 'mecab'
      MeCab::Tagger.new("-d #{`mecab-config --dicdir`.chomp}/mecab-ipadic-neologd/")
    rescue => e
      puts "Add gem 'mecab' to your Gemfile."
      raise e
    end

    def include_hashtags?(tweet)
      tweet.entities&.hashtags&.any?
    end

    def extract_hashtags(tweet)
      tweet.entities.hashtags.map { |h| h.text }
    end

    SYNONYM_WORDS = (
    %w(cosplay cosplayer cosplayers coser cos こすぷれ コスプレ レイヤ レイヤー コスプレイヤー レイヤーさん).map { |w| [w, 'coplay'] } +
        %w(tsukuba tkb).map { |w| [w, 'tsukuba'] } +
        %w(waseda 早稲田 早稲田大学).map { |w| [w, 'waseda'] } +
        %w(keio 慶應 慶應義塾).map { |w| [w, 'keio'] } +
        %w(gakusai gakuensai 学祭 学園祭).map { |w| [w, 'gakusai'] } +
        %w(kosen kousen).map { |w| [w, 'kosen'] } +
        %w(anime アニメ).map { |w| [w, 'anime'] } +
        %w(photo photos).map { |w| [w, 'photo'] } +
        %w(creator creater クリエイター).map { |w| [w, 'creator'] } +
        %w(illustrator illustrater 絵師).map { |w| [w, 'illustrator'] } +
        %w(artist art artists アート 芸術).map { |w| [w, 'artist'] } +
        %w(design デザイン).map { |w| [w, 'design'] } +
        %w(kawaii かわいい).map { |w| [w, 'kawaii'] } +
        %w(idol あいどる アイドル 美人).map { |w| [w, 'idol'] } +
        %w(music musician musicians dj netlabel label レーベル おんがく 音楽家 音楽).map { |w| [w, 'music'] } +
        %w(engineer engineers engineering えんじにあ tech 技術 技術系 hacker coder programming programer programmer geek rubyist ruby scala java lisp).map { |w| [w, 'engineer'] } +
        %w(internet インターネット).map { |w| [w, 'internet'] }
    ).to_h

    def normalize_synonym(words)
      words.map { |w| SYNONYM_WORDS.has_key?(w) ? SYNONYM_WORDS[w] : w }
    end
  end
end