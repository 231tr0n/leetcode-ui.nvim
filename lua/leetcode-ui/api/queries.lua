--- *LeetCodeQueries* All GraphQL queries
---

-- |leetcode-ui-api-queries| All GraphQL queries in one place.
-- Field names are kept in sync with LeetCode's API (verified live on 2026-11).
-- Lua identifiers use snake_case fields aliased from their camelCase names.

-- Module design:
local LeetCodeQueries = {}

LeetCodeQueries.auth = [[
      query globalData {
        userStatus {
          id: userId
          name: username
          is_signed_in: isSignedIn
          is_premium: isPremium
          is_verified: isVerified
        }
      }
]]

LeetCodeQueries.qot = [[
      query questionOfToday {
        todayRecord: activeDailyCodingChallengeQuestion {
          question {
            question_id: questionId
            title_slug: titleSlug
          }
        }
      }
]]

LeetCodeQueries.question = [[
      query getQuestionDetail($titleSlug: String!) {
        question(titleSlug: $titleSlug) {
          id: questionId
          frontend_id: questionFrontendId
          title
          title_slug: titleSlug
          is_paid_only: isPaidOnly
          difficulty
          content
          hints
          code_snippets: codeSnippets {
            lang
            lang_slug: langSlug
            code
          }
          testcase_list: exampleTestcaseList
          meta_data: metaData
          ac_rate: acRate
          stats
          topic_tags: topicTags {
            name
            slug
          }
          similar: similarQuestionList {
            difficulty
            title
            title_slug: titleSlug
            paid_only: isPaidOnly
          }
        }
      }
]]

LeetCodeQueries.problems = [[
      query problemsetQuestionList($categorySlug: String, $limit: Int, $skip: Int, $filters: QuestionListFilterInput) {
        problemsetQuestionList: questionList(
          categorySlug: $categorySlug
          limit: $limit
          skip: $skip
          filters: $filters
        ) {
          total: totalNum
          questions: data {
            ac_rate: acRate
            difficulty
            frontend_id: questionFrontendId
            is_favor: isFavor
            is_paid_only: isPaidOnly
            status
            title
            title_slug: titleSlug
            topic_tags: topicTags {
              name
              slug
            }
          }
        }
      }
]]

LeetCodeQueries.random_question = [[
      query randomQuestion($categorySlug: String, $filters: QuestionListFilterInput) {
        randomQuestion(categorySlug: $categorySlug, filters: $filters) {
          title_slug: titleSlug
          is_paid_only: isPaidOnly
        }
      }
]]

LeetCodeQueries.solved = [[
      query globalSolvedCounts($username: String!) {
        allQuestionsCount {
          difficulty
          count
        }
        matchedUser(username: $username) {
          solved_counts: submitStatsGlobal {
            acSubmissionNum {
              difficulty
              count
            }
          }
        }
      }
]]

LeetCodeQueries.calendar = [[
      query userCalendar($username: String!, $year: Int) {
        matchedUser(username: $username) {
          calendar: userCalendar(year: $year) {
            active_years: activeYears
            streak
            total_active_days: totalActiveDays
            dcc_badges: dccBadges {
              timestamp
              badge {
                name
                icon
              }
            }
            submission_calendar: submissionCalendar
          }
          solved_beats: problemsSolvedBeatsStats {
            difficulty
            percentage
          }
        }
      }
]]

LeetCodeQueries.skills = [[
      query skillStats($username: String!) {
        matchedUser(username: $username) {
          tag_problems_counts: tagProblemCounts {
            advanced {
              tag_name: tagName
              tag_slug: tagSlug
              problems_solved: problemsSolved
            }
            intermediate {
              tag_name: tagName
              tag_slug: tagSlug
              problems_solved: problemsSolved
            }
            fundamental {
              tag_name: tagName
              tag_slug: tagSlug
              problems_solved: problemsSolved
            }
          }
        }
      }
]]

LeetCodeQueries.languages = [[
      query languageStats($username: String!) {
        matchedUser(username: $username) {
          language_problem_count: languageProblemCount {
            language_name: languageName
            problems_solved: problemsSolved
          }
        }
      }
]]

LeetCodeQueries.streak = [[
      query getStreakCounter {
        streakCounter {
          streak_count: streakCount
          days_skipped: daysSkipped
          today_completed: currentDayCompleted
        }
      }
]]

return LeetCodeQueries
