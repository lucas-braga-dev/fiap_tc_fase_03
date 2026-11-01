package main

import (
	"fmt"
	"testing"
)

func TestEvaluationRespectsFlagAndPercentage(t *testing.T) {
	app := &App{}
	for _, test := range []struct {
		name string
		flag *Flag
		rule *TargetingRule
		want bool
	}{
		{"missing flag", nil, nil, false},
		{"disabled flag", &Flag{Name: "checkout", IsEnabled: false}, nil, false},
		{"enabled without rule", &Flag{Name: "checkout", IsEnabled: true}, nil, true},
		{"zero percent", &Flag{Name: "checkout", IsEnabled: true}, &TargetingRule{IsEnabled: true, Rules: Rule{Type: "PERCENTAGE", Value: float64(0)}}, false},
		{"all users", &Flag{Name: "checkout", IsEnabled: true}, &TargetingRule{IsEnabled: true, Rules: Rule{Type: "PERCENTAGE", Value: float64(100)}}, true},
		{"invalid percentage", &Flag{Name: "checkout", IsEnabled: true}, &TargetingRule{IsEnabled: true, Rules: Rule{Type: "PERCENTAGE", Value: "100"}}, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			got := app.runEvaluationLogic(&CombinedFlagInfo{Flag: test.flag, Rule: test.rule}, "user-123")
			if got != test.want {
				t.Fatalf("got %t, want %t", got, test.want)
			}
		})
	}
}

func TestBucketsAreStableAndWithinRange(t *testing.T) {
	for i := 0; i < 1000; i++ {
		input := fmt.Sprintf("user-%d:checkout", i)
		bucket := getDeterministicBucket(input)
		if bucket < 0 || bucket >= 100 {
			t.Fatalf("out of range: %d", bucket)
		}
		if getDeterministicBucket(input) != bucket {
			t.Fatal("unstable allocation")
		}
	}
}
