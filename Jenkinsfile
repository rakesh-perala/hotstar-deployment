pipeline {

    agent any

    environment {
        AWS_REGION = 'ap-south-1'
        EKS_CLUSTER_NAME = 'devops-eks-cluster'
    }

    stages {

        stage('Git Checkout') {
            steps {
                git branch: 'main',
                    url: ''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    aws eks update-kubeconfig \
                      --region ${AWS_REGION} \
                      --name ${EKS_CLUSTER_NAME}

                    kubectl apply -f deployment.yaml
                    kubectl apply -f service.yaml
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    kubectl get deployment
                    kubectl get pods -o wide
                    kubectl get service
                '''
            }
        }
    }

    post {
        success {
            echo 'Hotstar application deployed successfully to EKS.'
        }

        failure {
            echo 'Hotstar application deployment failed.'
        }
    }
}

