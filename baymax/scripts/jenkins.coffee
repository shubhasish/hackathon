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
# Contributor:
#   shubhashish

querystring = require 'querystring'

# Holds a list of jobs, so we can trigger them with a number
# instead of the job's name. Gets populated on when calling
# list.
jobList = []
crypto = require 'crypto'
algorithm = 'aes-256-ctr'

encrypt = (text) ->
  cipher = crypto.createCipher(algorithm,'apple')
  crypted = cipher.update(text.trim(),'utf8','hex')
  crypted += cipher.final('hex')
  crypted

decrypt = (text) ->
  decipher = crypto.createDecipher(algorithm,'apple')
  decrypted = decipher.update(text.trim(),'hex','utf8')
  decrypted += decipher.final('utf8')
  decrypted

setAuth = (msg) ->
  user_id = msg.envelope.user.id
  user = (msg.match[1].split " ")[0]
  password = (msg.match[1].split " ")[1]

  msg.robot.brain.data.users[user_id].jenkins_username = user
  msg.robot.brain.data.users[user_id].jenkins_password = encrypt(password)
  
  msg.reply "Authentication set for #{user_id}"

resetAuth = (msg) ->
  user_id = msg.envelope.user.id
  name = msg.envelope.user.name
  msg.robot.brain.data.users[user_id].jenkins_username = ""
  msg.robot.brain.data.users[user_id].jenkins_password = ""
  
  msg.reply "Authentication re-set for #{user_id}"

getAuth = (msg) ->
  user_id = msg.envelope.user.id
  username = (msg.robot.brain.data.users[user_id].jenkins_username).trim()
  password = (decrypt(msg.robot.brain.data.users[user_id].jenkins_password)).trim()

  auth = username + ":" + password
  auth



getUser = (msg) ->
  
  user_id = msg.envelope.user.id
  user_name = msg.envelope.user.name
  #user = (msg.match[1].split " ")[0]
  #password = (msg.match[1].split " ")[1]

  user = msg.robot.brain.data.users[user_id].jenkins_username 
  #msg.robot.brain.data.users[user_id].jenkins_password = password
  
  msg.reply "Username for #{user_name} is #{user}"

jenkinsBuildById = (msg) ->
  # Switch the index with the job name
  job = jobList[parseInt(msg.match[1]) - 1]

  if job
    msg.match[1] = job
    jenkinsBuild(msg)
  else
    msg.reply "I couldn't find that job. Try `jenkins list` to get a list."

jenkinsBuild = (msg, buildWithEmptyParameters) ->
    auth = getAuth(msg)
    url = process.env.HUBOT_JENKINS_URL
    job = querystring.escape msg.match[1]
    params = msg.match[3]
    command = if buildWithEmptyParameters then "buildWithParameters" else "build"
    path = if params then "#{url}/job/#{job}/buildWithParameters?#{params}" else "#{url}/job/#{job}/#{command}"
    req = msg.http(path)

    if auth
      auth = new Buffer(auth).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.post() (err, res, body) ->
        if err
          msg.reply "Jenkins says: #{err}"
        else if 200 <= res.statusCode < 400 # Or, not an error code.
          msg.reply "(#{res.statusCode}) Build started for #{job} #{url}/job/#{job}"
        else if 400 == res.statusCode
          jenkinsBuild(msg, true)
        else if 404 == res.statusCode
          msg.reply "Build not found, double check that it exists and is spelt correctly."
        else
          msg.reply "Jenkins says: Status #{res.statusCode} #{body}"

jenkinsDescribe = (msg) ->
    auth = getAuth(msg)
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]

    path = "#{url}/job/#{job}/api/json"

    req = msg.http(path)

    if auth
      auth = new Buffer(auth).toString('base64')
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
            if auth
              auth = new Buffer(auth).toString('base64')
              req.headers Authorization: "Basic #{auth}"

            req.header('Content-Length', 0)
            req.get() (err, res, body) ->
                if err
                  msg.send "Jenkins says: #{err}"
                else
                  response = ""
                  try
                    content = JSON.parse(body)
                    console.log(JSON.stringify(content, null, 4))
                    jobstatus = content.result || 'PENDING'
                    jobdate = new Date(content.timestamp);
                    response += "LAST JOB: #{jobstatus}, #{jobdate}\n"

                    msg.send response
                  catch error
                    msg.send error

          catch error
            msg.send error

jenkinsLast = (msg) ->
    auth = getAuth(msg)
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]

    path = "#{url}/job/#{job}/lastBuild/api/json"

    req = msg.http(path)

    if auth
      auth = new Buffer(auth).toString('base64')
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

jenkinsHelp = (msg) ->
    
    botName = msg.robot.name
    
    help = "#{botName} jenkins b <jobNumber> - builds the job specified by jobNumber. List jobs to get number.\n
    #{botName} jenkins build <job> - builds the specified Jenkins job\n
    #{botName} jenkins build <job>, <params> - builds the specified Jenkins job with parameters as key=value&key2=value2\n
    #{botName} jenkins list <filter> - lists Jenkins jobs\n
    #{botName} jenkins describe <job> - Describes the specified Jenkins job\n
    #{botName} jenkins last <job> - Details about the last build for the specified Jenkins job"
    msg.send help

jenkinsList = (msg) ->
    auth = getAuth(msg)
    
    url = process.env.HUBOT_JENKINS_URL

    filter = new RegExp(msg.match[2], 'i')
    req = msg.http("#{url}/api/json")

    if auth
      auth = new Buffer(auth).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.get() (err, res, body) ->
        
        response = ""
        if err
          msg.send "Jenkins says: #{err}"
        else
          try
            content = JSON.parse(body)
            
            for job in content.jobs
              # Add the job to the jobList
              index = jobList.indexOf(job.name)

              if index == -1
                jobList.push(job.name)
                index = jobList.indexOf(job.name)

              state = if job.color == "red"
                        "FAIL"
                      else if job.color == "aborted"
                        "ABORTED"
                      else if job.color == "aborted_anime"
                        "CURRENTLY RUNNING"
                      else if job.color == "red_anime"
                        "CURRENTLY RUNNING"
                      else if job.color == "blue_anime"
                        "CURRENTLY RUNNING"
                      else "PASS"

              if (filter.test job.name) or (filter.test state)
                response += "[#{index + 1}] #{state} #{job.name}\n"
            msg.send response
          catch error
            
            msg.send body

module.exports = (robot) ->
  robot.respond /j(?:enkins)? build ([\w\.\-_ ]+)(, (.+))?/i, (msg) ->
    jenkinsBuild(msg, false)

  robot.respond /j(?:enkins)? b (\d+)/i, (msg) ->
    jenkinsBuildById(msg)

  robot.respond /j(?:enkins)? list( (.+))?/i, (msg) ->
    jenkinsList(msg)

  robot.respond /j(?:enkins)? describe (.*)/i, (msg) ->
    jenkinsDescribe(msg)

  robot.respond /j(?:enkins)? last (.*)/i, (msg) ->
    jenkinsLast(msg)

  robot.respond /j(?:enkins)? help/i, (msg) ->
    jenkinsHelp(msg)

  robot.respond /j(?:enkins)? set-auth (.*)/i, (msg) ->
    setAuth(msg)

  robot.respond /j(?:enkins)? get-auth/i, (msg) ->
    getUser(msg)

  robot.respond /j(?:enkins)? reset-auth/i, (msg) ->
    resetAuth(msg)

  robot.jenkins = {
    list: jenkinsList,
    build: jenkinsBuild
    describe: jenkinsDescribe
    last: jenkinsLast
    
  }