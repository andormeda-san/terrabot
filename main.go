package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"strings"

	"github.com/nlopes/slack"
)

const (
	tokenID           = "xxx-xxx-xxx-xxx"
	VerificationToken = "xxx"
	Port              = ":xx"
	botID             = "<@xxx>"
	channelID         = "xxx"
)

// Slackparams is slack parameters
type SlackListener struct {
	botID     string
	channelID string
	client    *slack.Client
	rtm       *slack.RTM
}

// LstenAndResponse listens slack events and response
// particular messages. It replies by slack message button.
func (s *SlackListener) ListenAndResponse() {
	rtm := s.client.NewRTM()

	// Start listening slack events
	go rtm.ManageConnection()

	// Handle slack events
	for msg := range rtm.IncomingEvents {
		switch ev := msg.Data.(type) {
		case *slack.MessageEvent:
			if err := s.ValidateMessageEvent(ev); err != nil {
				log.Printf("[ERROR] Failed to handle message: %s", err)
			}
		}
	}
}

// ValidateMessageEvent is Validate Message Event
func (s *SlackListener) ValidateMessageEvent(ev *slack.MessageEvent) error {
	// Only response in specific channel. Ignore else.
	if ev.Channel != s.channelID {
		log.Printf("%s %s", ev.Channel, ev.Msg.Text)
		return nil
	}

	// Only response mention to bot. Ignore else.
	if !strings.HasPrefix(ev.Msg.Text, s.botID) {
		log.Printf("%s %s", ev.Channel, ev.Msg.Text)
		return nil
	}

	bytes, err := ioutil.ReadFile("menu.json")
	if err != nil {
		log.Fatal(err)
	}

	var attachment = slack.Attachment{}
	if err := json.Unmarshal(bytes, &attachment); err != nil {
		log.Fatal(err)
	}
	params := slack.MsgOptionAttachments(attachment)
	if _, _, err := s.client.PostMessage(ev.Channel, params); err != nil {
		return fmt.Errorf("failed to post message: %s", err)
	}
	return nil
}

func main() {
	client := slack.New(tokenID)

	slackListener := &SlackListener{
		client:    client,
		botID:     botID,
		channelID: channelID,
	}

	go slackListener.ListenAndResponse()

	// Register handler to receive interactive message
	// responses from slack (kicked by user action)
	http.Handle("/interaction", interactionHandler{
		verificationToken: VerificationToken,
	})

	log.Printf("[INFO] Server listening on :%s", Port)
	if err := http.ListenAndServe(Port, nil); err != nil {
		log.Printf("[ERROR] %s", err)
	}
}
