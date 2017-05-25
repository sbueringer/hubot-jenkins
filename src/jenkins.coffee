# Description:
#   Interact with your Jenkins CI server
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_JENKINS_URL
#   HUBOT_JENKINS_AUTH
#
#   Auth should be in the "user:password" format.
#
# Commands:
#   hubot jenkins b <jobNumber> - builds the job specified by jobNumber. List jobs to get number.
#   hubot jenkins build <job> - builds the specified Jenkins job
#   hubot jenkins build <job>, <params> - builds the specified Jenkins job with parameters as key=value&key2=value2
#   hubot jenkins list <filter> - lists Jenkins jobs
#   hubot jenkins describe <job> - Describes the specified Jenkins job
#   hubot jenkins last <job> - Details about the last build for the specified Jenkins job

#
# Author:
#   dougcole

querystring = require 'querystring'

# Holds a list of jobs, so we can trigger them with a number
# instead of the job's name. Gets populated on when calling
# list.
jobList = []

jenkinsBuildById = (msg) ->
  # Switch the index with the job name
  job = jobList[parseInt(msg.match[1]) - 1]

  if job
    msg.match[1] = job
    jenkinsBuild(msg)
  else
    msg.reply "I couldn't find that job. Try `jenkins list` to get a list."

jenkinsBuild = (msg, buildWithEmptyParameters) ->
  url = process.env.HUBOT_JENKINS_URL
  params = msg.match[3]
  command = if buildWithEmptyParameters then "buildWithParameters" else "build"

  #<jenkins-url>/job/i3/job/i3-keycloak/job/develop/build
  # i3:i3-keycloak:develop
  # /job/i3/job/i3-keycloak/job/develop

  jobUrl = ""
  jobUrlParts = msg.match[1].split ":"
  for jobUrlPart in jobUrlParts
    escapedJobUrlParts = querystring.escape jobUrlPart
    jobUrl += "/job/" + escapedJobUrlParts

  path = if params then "#{url}#{jobUrl}/buildWithParameters?#{params}" else "#{url}#{jobUrl}/#{command}"

  req = msg.http(path)

  if process.env.HUBOT_JENKINS_AUTH
    auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
    req.headers Authorization: "Basic #{auth}"

    reqCrumb = msg.http("#{url}/crumbIssuer/api/json")
    reqCrumb.headers Authorization: "Basic #{auth}"
    reqCrumb.get() (err, res, body) ->
      if err
        msg.reply "Jenkins says: #{err}"
      else if 200 <= res.statusCode < 400 # Or, not an error code.
        content = JSON.parse(body)
        console.log body
        console.log "Got Crumb #{content.crumbRequestField} #{content.crumb}"
        req.header(content.crumbRequestField, content.crumb)
        console.log "req:"+ JSON.stringify(req)
        sendBuildTrigger(msg, req, "#{url}#{jobUrl}")
      else if 400 == res.statusCode
        msg.reply "400"
      else if 404 == res.statusCode
        msg.reply "404"
      else
        msg.reply "Jenkins says: Status #{res.statusCode} #{body}"
  else
    sendBuildTrigger(msg, req, "#{url}#{jobUrl}")

sendBuildTrigger = (msg, req, jobLink) ->
  req.header('Content-Length', 0)
  req.post() (err, res, body) ->
    if err
      msg.reply "Jenkins says: #{err}"
    else if 200 <= res.statusCode < 400 # Or, not an error code.
      msg.reply "(#{res.statusCode}) Build started for [#{msg.match[1]}](#{jobLink})"
    else if 400 == res.statusCode
      jenkinsBuild(msg, true)
    else if 404 == res.statusCode
      msg.reply "Build not found, double check that it exists and is spelt correctly."
    else
      msg.reply "Jenkins says: Status #{res.statusCode} #{body}"

jenkinsDescribe = (msg) ->
  url = process.env.HUBOT_JENKINS_URL
  job = msg.match[1]

  path = "#{url}/job/#{job}/api/json"

  req = msg.http(path)

  if process.env.HUBOT_JENKINS_AUTH
    auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
    req.headers Authorization: "Basic #{auth}"

  req.header('Content-Length', 0)
  req.get() (err, res, body) ->
    if err
      msg.send "Jenkins says: #{err}"
    else
      response = ""
      try
        content = JSON.parse(body)
        response += "JOB: #{content.displayName}\n"
        response += "URL: #{content.url}\n"

        if content.description
          response += "DESCRIPTION: #{content.description}\n"

        response += "ENABLED: #{content.buildable}\n"
        response += "STATUS: #{content.color}\n"

        tmpReport = ""
        if content.healthReport.length > 0
          for report in content.healthReport
            tmpReport += "\n  #{report.description}"
        else
          tmpReport = " unknown"
        response += "HEALTH: #{tmpReport}\n"

        parameters = ""
        for item in content.actions
          if item.parameterDefinitions
            for param in item.parameterDefinitions
              tmpDescription = if param.description then " - #{param.description} " else ""
              tmpDefault = if param.defaultParameterValue then " (default=#{param.defaultParameterValue.value})" else ""
              parameters += "\n  #{param.name}#{tmpDescription}#{tmpDefault}"

        if parameters != ""
          response += "PARAMETERS: #{parameters}\n"

        msg.send response

        if not content.lastBuild
          return

        path = "#{url}/job/#{job}/#{content.lastBuild.number}/api/json"
        req = msg.http(path)
        if process.env.HUBOT_JENKINS_AUTH
          auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
          req.headers Authorization: "Basic #{auth}"

        req.header('Content-Length', 0)
        req.get() (err, res, body) ->
          if err
            msg.send "Jenkins says: #{err}"
          else
            response = ""
            try
              content = JSON.parse(body)
              jobstatus = content.result || 'PENDING'
              jobdate = new Date(content.timestamp);
              response += "LAST JOB: #{jobstatus}, #{jobdate}\n"

              msg.send response
            catch error
              msg.send error

      catch error
        msg.send error

jenkinsLast = (msg) ->
  url = process.env.HUBOT_JENKINS_URL
  job = msg.match[1]

  path = "#{url}/job/#{job}/lastBuild/api/json"

  req = msg.http(path)

  if process.env.HUBOT_JENKINS_AUTH
    auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
    req.headers Authorization: "Basic #{auth}"

  req.header('Content-Length', 0)
  req.get() (err, res, body) ->
    if err
      msg.send "Jenkins says: #{err}"
    else
      response = ""
      try
        content = JSON.parse(body)
        response += "NAME: #{content.fullDisplayName}\n"
        response += "URL: #{content.url}\n"

        if content.description
          response += "DESCRIPTION: #{content.description}\n"

        response += "BUILDING: #{content.building}\n"

        msg.send response

jenkinsList = (msg) ->
  url = process.env.HUBOT_JENKINS_URL
  filter = new RegExp(msg.match[2], 'i')

  if process.env.HUBOT_JENKINS_JOB_DEPTH
    depth = parseInt process.env.HUBOT_JENKINS_JOB_DEPTH, 10
  else
    depth = 1

  suffix = "?tree="
  for i in [1...(depth + 1)] by 1
    if i < depth
      suffix += "jobs[name,buildable,color,"
    else
      suffix += "jobs[name,buildable,color"
  for i in [1...(depth + 1)] by 1
    suffix += "]"

  req = msg.http("#{url}/api/json" + suffix)

  if process.env.HUBOT_JENKINS_AUTH
    auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
    req.headers Authorization: "Basic #{auth}"

  req.get() (err, res, body) ->
    if err
      msg.send "Jenkins says: #{err}"
    else
        content = JSON.parse(body)
        res = parseJobs(0, "", content.jobs, filter)
        msg.send res

parseJobs = (depth, prefix, jobs, filter) ->
  res = ""
  for job in jobs
    if depth > 0 or filter.test job.name
      for i in [1...(depth + 1)] by 1
        res += "\t"
      if job._class == "com.cloudbees.hudson.plugins.folder.Folder"
        res += "Folder #{prefix}#{job.name}:\n"
      else
        if job._class == "org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject"
          res += "MultiBranchProject #{prefix}#{job.name}:\n"
        else
          index = jobList.indexOf (prefix+job.name)
          if index == -1
            jobList.push(prefix+job.name)
            index = jobList.indexOf(prefix+job.name)
          state = if job.color == "red" then "FAIL" else "PASS"
          res += "[#{index + 1}] #{state} #{prefix}#{job.name}\n"

    if job.jobs
      res += parseJobs(depth+1, prefix + job.name + ":", job.jobs, filter)

  return res

module.exports = (robot) ->
  robot.respond /j(?:enkins)? build ([\:\w\.\-_ ]+)(, (.+))?/i, (msg) ->
    jenkinsBuild(msg, false)

  robot.respond /j(?:enkins)? b (\d+)/i, (msg) ->
    jenkinsBuildById(msg)

  robot.respond /j(?:enkins)? list( (.+))?/i, (msg) ->
    jenkinsList(msg)

  robot.respond /j(?:enkins)? describe (.*)/i, (msg) ->
    jenkinsDescribe(msg)

  robot.respond /j(?:enkins)? last (.*)/i, (msg) ->
    jenkinsLast(msg)

  robot.jenkins = {
    list: jenkinsList,
    build: jenkinsBuild
    describe: jenkinsDescribe
    last: jenkinsLast
  }
