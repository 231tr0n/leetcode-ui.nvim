--- *leetcode-ui-api-queries* All GraphQL queries
---
--- All GraphQL query strings in one place. Field names are kept in sync with
--- LeetCode's API. Most normalized fields are aliased to snake_case; some
--- top-level objects retain LeetCode's camelCase names.
---@tag LeetCodeQueries
---@toc_entry GraphQL queries

local LeetCodeQueries = {}

LeetCodeQueries.auth = [[
      query globalData {
        userStatus {
          id: userId
          name: username
          is_signed_in: isSignedIn
          is_premium: isPremium
        }
      }
]]

LeetCodeQueries.qot = [[
      query questionOfToday {
        todayRecord: activeDailyCodingChallengeQuestion {
          question {
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
          status
          content
          hints
          code_snippets: codeSnippets {
            lang
            lang_slug: langSlug
            code
          }
          testcase_list: exampleTestcaseList
          ac_rate: acRate
          topic_tags: topicTags {
            name
            slug
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
        }
      }
]]

return LeetCodeQueries
