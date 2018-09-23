ChooChoo Slack Bot
------------------

_Provides real-time information on UK train lines and services, via Slack messages._

![image](https://user-images.githubusercontent.com/193455/45926635-5670f400-bf1d-11e8-99af-3c86b59eef73.png)

### Set-Up

* Ruby
* An account for the [Realtime Trains API](https://api.rtt.io/) to retrieve data
* A token for a [Slack application](https://api.slack.com/) to post to a channel

### Usage

`ruby choo-choo.rb --morning --evening`

### Notes

* Work In Progress - working prototype with no automated tests
* Train lines and trains are grouped into a `morning` and `evening` set
* Manually run, without a Slack bot interface (yet...)
